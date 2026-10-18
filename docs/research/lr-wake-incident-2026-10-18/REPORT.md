# Overnight limit-recover pane failures — 2026-10-18 incident report

Scope (frozen): repair the live panes left by the overnight limit-recover run (accounts next/next4 to next2/next3), research the root cause and long-term fix for complaints a–e, and land the fixes as implementation waves.


**Governing thought.** Overnight the in-place move recycle raced itself, and an agent's rescue loop multiplied the damage. The recycle's detached watcher typed `/exit` on a silent 60 s timer before the foreground had committed, and the foreground's load hold then killed that watcher before it typed the relaunch. The agent then built a `--tab` rescue loop that obeyed a capacity refusal which only releases when it is re-run, and that loop turned every stranded session into hidden tabs of plain shells. The one structural fix is a single commit-and-admit contract. Nothing types `/exit` until the foreground has written its commit marker. Nothing opens a pane that admission has not already granted. A pane that ends up running no Claude closes itself through the fullscreen guard.

Synthesis of findings a, b, c, c2, d, e, f, g and h, their adversarial passes, and z-critic. Code citations are at b2a295c94 (this worktree). `main` is 2 commits ahead: dc74a6c22 moves `lr-handoff.sh` :2026 to :2042, and 11b063908 moves `bin/cc-lr` :1272 to :1288. **M** = measured (the source is named). **I** = inferred. I re-read the live state at 13:48–13:50 CDT with `uptime`, `kitten @ ls`, `kitten @ get-text --match id:350`, `launchctl list`, `pgrep` and `ls ~/.reso/limit-recover/move`. Those readings are cited as "M live".

**No work is confirmed lost** (M: h, z-critic G3). Every stranded session either continues in a successor or closed with "Good to close: yes". Three sessions are **at risk**:

- f06b5e9b, pane 350: the modal is up and this is the only copy.
- e52f1f63, pane 430: it is waiting on an unanswered operator question.
- 9f6593c5, pane 258: it has been frozen for 7 days.

## 1. Root causes (deduplicated, confidence after verification)

**Which root cause explains which symptom:**

| Symptom | Root causes |
|---|---|
| a, the failed recycle | RC1, plus RC4 (the false banner) |
| b, tabs | RC3, plus RC2 and RC7 (what drove the re-fires) |
| c, husk panes | RC2, RC1, RC4 |
| c, the wall-of-text messages | RC8, plus RC2 and RC4 (the false lines) |
| d, the bg-work modal and a stuck `/exit` | RC1, plus RC6 (nobody noticed) |
| e, junk in the composer | RC5 (pane 430) and RC7 (pane 403) |

RC9 (load) amplifies RC1, RC2 and RC5.

**RC1. Recycle commit race: the watcher exits Claude before the foreground commits. 90%.** Symptoms: a, c, d.
- **How it fails.** The watcher is detached before the confirm (`handoff-fire.sh:3516`). Its wall-clock 60 s checkpoint fires the `retype` arm (`:11718-11746`), which writes no log row. On an empty composer that arm types `/exit` and Enter. The foreground is meanwhile still in its confirm, last read and load gate, which take 80–270 s at 8–30 load per core. The foreground then holds at load (`:18601-18603`). `hf_recycle_hold` (`:3615-3651`) unconfirms and then runs `hf_recycle_disarm`, which is a bare `kill` (`:3341`). Nothing re-checks the subject before either hold call (`:18595`, `:18603`). The only re-checks are at `:18589`, `:18615` and `:18638`. So:
  - Claude is already gone, the relaunch is cut off mid-typing, and the result is a bare shell.
  - With a background job, the result is the bg-work modal with nobody left to answer it.
  - When the read-back was missed, `/exit` is left unsent in the composer.
- **Who typed `/exit` (M).** `history.jsonl` records `/exit` as a submitted prompt in four sessions. The foreground never reached its own `/exit` in any of them.

  | Session | Time | history.jsonl |
  |---|---|---|
  | 2e9ed9f2 | 03:38:37Z | quaternary |
  | 2e9ed9f2 | 07:22:53Z | next |
  | e52f1f63 and 5232121f | 07:06:13Z | quaternary |
  | 22a76c8a | 07:22:38Z | next |

  This settles f's "same-second exits" (z-critic G1.1).
- **How widespread (M).**
  - 10 `recycle-held-load` rows carry `unconfirm rc 2`.
  - 24 of the 33 held recycles had a watcher alive for 60 s or more.
  - The watchers for panes 20, 22 and 242 answered the bg-work modal with "1" (stop tasks).
- **It repeated live (M).** Pane 350 got the modal again from batch 180746Z at 18:24–18:26Z, and the modal is **still up at 13:49 CDT** (M live). The first instance was pane 7 on 2026-10-17 (475d66ced).
- **Two lines lie to the reader:**
  - "The session stays alive" (`handoff-fire.sh:3635`);
  - "nothing was typed, a retry is safe" (`lr-handoff.sh:2026`).
- **Why it showed up now.**
  - The retype arm itself is old: 77864768f, 2026-08-22.
  - Three later changes exposed it:
    - 1376807f4 put the checkpoints on the wall clock;
    - 18910dd50 added the post-arm last read;
    - 2bb9817d0 added the post-arm load gate.
  - d58bb81d3 (the precheck hold) uses the same 8/core bound as the commit gate, with no hysteresis. Pane 350 passed the precheck at 7.36/core and then held at 8.72/core.
- **Why the relaunch is typed at all.** The move lane never stages a keystroke-free successor (`:4532`, "Resume, transplant and remote recycles never stage").

**RC2. Two admission gates per spawn, a release that only comes from re-running, no queue, and a runner that keeps the shell. 85%.** Symptoms: c (13 rescue husks plus pane 428), and what drove b.
- **The two gates disagree.** handoff-fire's outer gate admits and counts no tokens (`:10463`), and it mints no token for the launcher. The inner gate (`lr-fire-resume.sh:777-797`) then refuses with exit 9. `cc-pane-runner:179-181` keeps a shell on any non-zero rc.
- **The release can only be reached by re-running.** The budget is count-only (`capacity-admit.sh:404-430`, "no clock"). The text invites a retry: "re-run this exact command" (`lr-fire-resume.sh:790`) and "the next evaluation ADMITS" (`capacity-admit.sh:1637`).
- **Measured in the IDL (M):** 22 refuse/active and 6 admits by budget expiry. The 12 refused panes match the IDL refusal rows one for one.
- **The token wiring bug is still firing (M).** `lr-handoff.sh:1537` reads the token *record* as a path. That produced 12 or more `token ABSENT` rows, plus 3e929a81 at 18:25:44Z. Each orphan token inflates the in-flight count for 1020 s, and the bug strands reconciler relaunches directly (b102f5af was retried 4 times).
- **The budget key is shared across actors.** `direct-<sid>` is one key for everyone, so the rescue's refusals released the poller's spawn of pane 429.
- **The poller autofire has three gaps:**
  - it does not probe before it spawns;
  - it logs RESUMED before the rc is known (`lr-reset-poller.sh:2598-2603`);
  - its claim check sees only `--resume` argv, so it opened 428 as a **duplicate** of live 509e3aad (pane 28, pid 7301; M).

**RC3. No placement policy exists in code, and `--tab` is fleet doctrine. 80% on the mechanism; about 50% on prevention without RC2.** Symptom: b.
- **How agent `--tab` becomes a tab.** `--tab` is rewritten to `bg-tab` (`handoff-fire.sh:15195-15197`), which calls `kt_launch --type=tab` (`:17631`). Nothing counts panes or tabs.
- **Every existing guard is ineffective:**
  - The advisory at `:19356-19361` is dead code for autonomous fires.
  - The room/overflow logic (`:18282`, `:18319`) runs for headless fires only.
  - Overflow OS windows are not fullscreen (`:18215`; `os-window-state` has 0 hits).
  - `validate-bash` has no tab rule.
  - `config/kitty.conf:930` still binds `cmd+t` to a new tab.
- **The doctrine that taught it:**
  - `commands/handoff.md:500` and `:547-549` (overflow goes to a tab);
  - the stale `--help` at `:112-129`;
  - lead briefs that say "use --tab if splits time out";
  - 9 bg-tab rows on 10-17 from 3 pids, before 03:02Z.
- **Counts (M):** 22 bg-tab spawn rows overnight.
- **Live layout now (M live):** OS windows 16 and 20 have **5 panes** each, and OS window 26 has 1. Fullscreen state cannot be read through `kitten @ ls`.

**RC4. Pane verdicts lie, and the sanctioned closer cannot close. 85%.** Symptoms: c (the "in-between" state) and the banner in a.
- **The watchdog misclassifies.** It labels a STRANDED move death `RECYCLE/clean-exit` and paints "✅ CLOSED CLEANLY … safe to close" (`lead-crash-watchdog.sh:1733`). That happened 28 s after lr had recorded STRANDED, and it paints before the closer decides (`:1790`/`:1793`). The resume hint uses the source account (`:1674`), so it printed `claude4` for a session that lives on next2.
- **`cc-pane-close` refused all 18 husks (M, h defect 1).** It has no "never launched" arm, it reads only the source store's 4 KB stub, and it cannot see custody after a move.
- **`cc-husk-sweep` says RESUME for a session that already recycled** (pane 332). Following it would have made a split brain.
- **`lr-fire-resume.sh:1859-1870` always runs `exec $SHELL`** and prints "ordinary shell", even on a planned exit.
- **A raw close hit the last pane of a fullscreen OS window** (pane 428). That is the trigger of the 2026-10-15 kitty crash (h defect 7).

**RC5. A long prompt is delivered as unframed keystrokes, and the readers recognise only one chip. 75% on the origin; 50% on why the Enter was lost.** Symptoms: e (pane 430), and d (the carried `/exit`).
- **How the junk got there.** `lr-fire-resume.sh:807` flattens the 2,050-byte brief, and `:1555` sends it as raw keys with no `ESC[200~` framing. Claude Code collapsed it into `[Pasted text #1][Pasted text #2]re) -->`.
- **Why it blocks the pane.** The reader strips only one chip (`:1115`), and `composer-intent.sh:64-66` anchors on one chip. So the box classifies as DRAFT (rc 1), and every verified rail holds forever instead of typing over it.
- **Why nobody noticed.** Runs with no token break out at `:1665` before the look/re-CR loop, and log nothing (`:1132`, `:1148`).
- **This is the fourth time.** The same collapse hit pane 751, pane 815 and 4fe9935f (`:993-1021`), and each was patched in the reader.
- **Most other composer text is not junk (M, `get-text --ansi`).** On panes 23, 25, 344, 429, 433 and others it is Claude Code's dim suggestion (`ESC[22;2m`). `LR_SCREEN_SH` reads without `--ansi` (`:1033`, `:1079`), so it may read such a suggestion as DRAFT (I).
- **h defect 4 (`/goal clear` typed on pane 23) is unproven.** It is probably the same dim suggestion (z-critic G3).

**RC6. Lane coordination: several drivers per session, cohorts that never expire, and a census that ignores modals. 85%.** Symptoms: c (pane 23), d.
- **Three drivers on one session.** 3e929a81 was driven by drain batch 072521Z, the poller REQUEST at 07:47Z and the reconciler cohort `next4-7d-1792314000`. It ended as a guarded husk for about 10 h. The reconciler never takes the `runs/by-sid` claim.
- **The cohort outlived the limit.** It was still holding the session 11 h later, after next4 had reset (h defect 3).
- **The census waits on a modal.** `bin/cc-lr:1272` and `lr-upgrade.sh:746` and `:1080` map an unreadable composer to `composer-unknown`, which means wait. Pane 350 sat at the modal through 3 × 3600 s waits with no page (d).
- **The draft-carry carries a rail artefact.** It has no `/exit` class (`composer-intent.sh:45-80`, commit 78d47b174), so it typed 384's leftover `/exit` into the successor.

**RC7. An agent worked outside the rails, and the tools gave it silent or false signals. 85% on attribution.** Symptoms: b, c, e (pane 403).
- **What the pane-344 lead did** (620db313, then 2cc3a7fa):
  - queued 22 batches;
  - installed `com.reso.drain-to-next3` at 06:35Z, which placed 11 more batches and ran 30 or more next4 rotates ending rc=1;
  - wrote `/tmp/lr-rescue/` and ran 25 `--tab` fires, against the STRANDED text's "do NOT hand-spawn";
  - created 403's cwd, `whose\n…`, with a `sed` at 07:13:12Z.
- **What the tools hid from it:**
  - handoff-fire accepts `--cwd` unvalidated (`:14529`).
  - `FIRE_PARKED_RE` (`:5790`) is blind to `zsh:cd:1:`.
  - The engagement window adds up sleep intervals instead of reading the clock (`:6279`, `:6339`), so 480 s stretched to 49 min.
- **The pattern predates last night.** `/tmp/resume-9f6593c5-retry.sh` dates from 10-17 03:24.
- **f overstated the single origin (f-adversarial).** Pane 434 came from pane 433, panes 428 and 429 came from the poller, and the strands are RC1, which is independent of pane 344.

**RC8. No shared renderer for messages. 65% as the cause of the wall of text.** Symptom: c (messages).
- **Volume.** About 12 producers each print their own diagnosis. Pane 435 spends 7 lines (about 20 rows at 57 columns) on one fact. The Stop readout takes 20–27 rows. 26 of 54 panes are 57 columns or narrower.
- **False lines:**
  - the wrong knob is named at `lr-fire-resume.sh:791`;
  - class-B items past their deadline show as "auto-fire ≤24h" (`operator-readout.sh:1366-1374`) for 12 h, and nothing fired.
- **Palette.** The colours are forked, and SGR-2 is still used at `cc-lid:127` and `kitty-setup.sh:158`.
- **What this does not cover.** The two most damaging false banners belong to RC2 and RC4.

**RC9 (amplifier). Load has no owner, and the gates count the wrong thing. 70%.**
- **Load (M).** 84–121 at 13:12 with 76 claudes. 44.6 / 63.5 / 79.5 on 10 cores at 13:48 (M live).
- **Contributors (I, c2 §2.8):**
  - 39–43 TUIs;
  - 109 MCP processes;
  - 39 watchdog loops;
  - bats suites, which are running now (M live);
  - Dia automation.
- **What the gate counts.** It counts prompt-beat sessions even when they are blocked in `sleep`.

## 2. Origin map (pane → originating session or action)

| Pane (OS window) | Session | What the operator saw | Origin | RC |
|---|---|---|---|---|
| 332 (20) | 2e9ed9f2 | bare zsh, "ordinary shell", half-typed `: hfv-77512…` (a) | move 1: batch 030847Z, which pane 344/620db313 queued. Move 2: drain batch 070336Z-…-37630, at 07:20Z | 1 |
| 1 (5), 21 | e52f1f63, 5232121f | "CLOSED CLEANLY", hint `claude4` | pane-344 batch 064955Z-…-7738. Watcher `/exit` at 07:06:13Z | 1, 4 |
| 242 (5) | 0d7c9a19 (finished) | CLOSED CLEANLY, hint names the wrong store | drain batch at 10:18Z (…-41444). Its watcher answered the modal "1" | 1, 4 |
| 20, 22, 24, 390 | various | relaunch cut off, modal answered "1" | drain and pane-344 batches, 02:08–10:39Z | 1 |
| 350 (21) | f06b5e9b (next) | bg-work modal, twice. **Still up at 13:49** (d) | drain batches 143348Z-…-33124 (14:37Z) and 180746Z-…-6778 (18:24Z) | 1, 6 |
| 384 (22) | 98e6f890 | `/exit` in the successor's composer (d) | 070336Z nudge left `/exit` unsent. The draft-carry retyped it at 16:51:54Z | 1, 5, 6 |
| 403 (18, tab) | 5232121f | `cd $'whose\n…'` failed (e) | the 2cc3a7fa `sed` at 07:13:12Z | 7 |
| 409–426, 435 (18, tabs) | 5232121f, e52f1f63, 22a76c8a, 2e9ed9f2 | 12 "REFUSING … N of 3" husks (b, c) | 2cc3a7fa `fire-round.sh` and `fire-next3-batch.sh` with `--tab`, 07:19–10:57Z | 2, 3, 7 |
| 376, 377 | 8db0e6f1, e739e5b5 | the first rescue tabs (later detached) | 620db313 `--tab`, 03:02Z | 3, 7 |
| 430 (18 → 25) | e52f1f63 | `[Pasted text #1][Pasted text #2]re) -->` (e) | 2cc3a7fa round at 10:05Z, then lr-fire-resume's raw key burst | 5 |
| 433, 442 (tabs) | 22a76c8a → 09e18eed, 2e9ed9f2 → fad30cb7 | live, but in tabs (b) | rescues admitted only by budget expiry, 10:44Z and 11:31Z | 2, 3 |
| 434 (+454) | 4a72e434 | tab (b) | 22a76c8a's own W2 `--tab` fire from 433, 10:49Z | 3 |
| 428 (24, alone) | 509e3aad, a duplicate | refusal husk in a 1-pane OS window | poller autofire 10:00:12Z, with no live-holder check | 2 |
| 429 (25, alone at first) | 5232121f | live, but a 1-pane OS window | poller autofire 10:04:31Z, released by the rescue's shared key | 2, 3 |
| 23 (5) | 3e929a81 FBAR | guarded husk for about 10 h | triple drive (drain, poller, reconciler). Relaunched on next3 by hand at about 13:20 | 6 |
| 258 (3) | 9f6593c5 | idle for 7 days, HELD:no-shell every hour | `/tmp/resume-9f6593c5-retry.sh`, 10-17 (pre-existing) | 2 |
| 401 (21) | operator shell | `cc-lr move` output | the operator, 06:55Z (by design) | — |
| 3, 374 / 445 | a3da0696, 7df606ba / 6f8d7bd2 | workers armed **now** / self-move actuating **now** (M live) | drain batch 180746Z / batch 184542Z requested by pane 445 | 1 (risk) |
| 456, 457 (18) | unknown (`claude.exe`) | new since 13:22 CDT | **not attributed** | — |

The 18 husks named in h were closed by the lead before 13:35. The tabs are merged: every OS window now has 1 tab (M live).

## 3. Immediate remediation for the live panes (ordered, safe first; describe only)

1. **Stop new damage. These are file writes only and type nothing into any pane.**
   - `touch ~/.reso/limit-recover/move/20261018T180746Z-next-next3-6778/abort`. M live: workers 80986 (a3da0696, pane 3, wait:background-job, which would raise the modal again) and 81633 (7df606ba, pane 374) are alive, and there is no abort file.
   - Pause the drain with `touch ~/.reso/limit-recover/listeners/drain-to-next3.off`. This is the operator's call (Q2). M live: the agent is still loaded, and it started a next4 rotate at 18:41:45Z after an rc=1. Accounts next and next4 are healthy and next3 is the hottest (z-critic G6).
   - Archive, with `mv` and not `rm`: `/tmp/lr-rescue/`, `/tmp/resume-9f6593c5-retry.sh` and `/tmp/fire-lr-344-successor.txt`, which still carries `--tab`. Nothing must re-run them.
   - **No in-place moves** until Wave A lands, or at least until the 5-minute load is below 6/core (M live: 6.35/core). Do not use `HF_RECYCLE_HOLD_LOAD_PER_CORE=off`, `CC_FIRE_CAPACITY_GATE=off` or `CC_ADMIT_GATE=off`.
   - Batch 184542Z (6f8d7bd2, pane 445) is that session's own proof run and is actuating now. Leave it to pane 445. Afterwards, grep its `handoff.log` for `(held: load)` together with `unconfirm rc 2`. If it stranded, re-drive it with `lr-fleet.sh --one 6f8d7bd2… --source-pane 445`.
2. **Pane 350 (f06b5e9b, the only copy, no watcher alive).** Do this after step 1.
   - Answer **"Stay"**, using the index read off the screen (`_pane_bgwork_index "Stay"`, `hooks/lib/pane-modal.sh`), and confirm it by read-back.
   - **Never "1".** It stops `cc-await-ping` and exits the only copy, with nothing armed to relaunch it.
   - Then leave the session on next, which is healthy now.
3. **Pane 344 (2cc3a7fa, the rescue lead).** Tell it the rescue is over, because every one of its targets is live. Release its Stop-hook goal. It must not run `fire-round.sh` again.
4. **Tell the operator about pane 430.** e52f1f63 is waiting on the operator's answer (backlog 661a8652d2f6). Do **not** re-deliver the rescue brief: its SELF-RETIRE block would close the session.
5. **Layout, always through `kitty-fullscreen-guard`** (kitty-pane-menu or `detach-window`, never a raw `close-window` on a last pane):
   - OS window 16 (8, 47, 246, 374, 445) and OS window 20 (25, 26, 340, 390, 397) each give up one pane to OS windows 7, 21 or 22, which have 3 panes each.
   - Fold OS window 26 (398, alone) into the remaining 3-pane window.
   - Check fullscreen by eye, because `kitten @ ls` does not expose it.
6. **Pane 258 (9f6593c5):** the operator decides (Q6). **0d7c9a19:** leave it closed. If it is ever wanted, run `claude3 --resume 0d7c9a19…`, because the transcript is on next3; do not use the banner's `claude`.
7. **Leave and track.**
   - Check that cohort `next4-7d-1792314000` has closed and that pane 23 is taking turns.
   - The stale lock `locks/2e9ed9f2….launch` names a dead pid (9481) and is harmless.
   - The `cc-registry` rows are inverted: closed panes 1, 21, 22, 242 and 409–435 still have rows, while live panes 19, 27 and 28 have none. The cause is unknown; Q9 tracks it.
8. **Sweep until Wave A lands.**
   - A bg-work modal gets "Stay".
   - A composer that reads exactly `/exit` gets `cc_tui_clear` with read-back.
   - Before clearing any composer text, confirm with `get-text --ansi` that it is not a dim suggestion (`ESC[22;2m`).

## 4. Long-term fixes as implementation waves

**Contracts every wave codes to.** These settle the conflicts z-critic raised in G4.
- **K1, commit marker.**
  - The foreground writes `$CMDFILE.exit-committed` (an epoch) immediately before its first exit actuator.
  - Every hold writes `$CMDFILE.exit-aborted` before it disarms.
  - Both sit beside the existing `$CMDFILE.confirmed`.
  - The watcher's checkpoints count from `exit-committed`.
  - `retype` stays, but runs only after the marker, only once, and through `hf_exit_readback`, which brings the undo and the receipt.
- **K2, hold yield.** The yield happens at the call sites (`:18595`, `:18603`). It never happens as a `return 0` inside `hf_recycle_hold`, because that falls through to `hf_exit_readback` (`:18646`).
- **K3, a refused or failed pane.**
  - Exit codes:
    - rc 75 means "queued": one durable `requests/<sid>.cc-lr.json` exists. It is written only when `LR_RUN_DIR` is unset, and only after deduping against `parked/`, `runs/by-sid/` and `requests/`.
    - rc 9 means "refused, and the run-dir owner retries".
  - `cc-pane-runner` writes `~/.claude/run/pane-exit/<window>.json` with `{rc, claude_started, launch_sha, ts}` on every exit.
  - It closes the pane only on rc 75, or when `claude_started=false` and an owed record exists.
  - It closes only a pane it created for this launch, and only through `kitty-fullscreen-guard --scope os-window`.
  - It never closes an in-place pane.
  - CORRECTED (2026-10-18, Wave B finding, checked at `lib/kitty-fs-kitten.py:101-105`): the guard call is `kitty-fullscreen-guard --scope pane --mode refuse`, not `--scope os-window`. `last_for["os-window"]` is always true, so `os-window` would refuse every close in a fullscreen window. `pane` refuses exactly when the pane is the OS window's last one, which is the 2026-10-15 crash trigger. The same applies to h defect 7 and to every husk closer.
- **K4, tokens.** The redeem fix and orphan expiry land before any new mint site.
- **K5, poller spawn.** The order is: live-beat holder check, then probe, then mint, then spawn.
- **K6, watchdog auto-close.** It closes only when `cc-find` shows a LIVE copy elsewhere. A tombstone alone gives a STRANDED banner plus an enqueue.
- **K7, load bounds.** Precheck 6/core, commit 8/core. No `=off` remedies.
- **K8, composer classes.** `rail-exit`, multi-chip `rail-token` and `rail-residue` are defined in Wave C and consumed by Wave G.

**Order.**
- **Tier 1** runs in parallel, with disjoint file sets: A, B, C, D, F, G, H. Land A and B first, because they stop new damage.
- **Tier 2:** E starts after A, B and D. H2 starts after B, C, E, F, G and H.
- **Tier 3:** S starts after A, C, E and H2. B2 starts after B.
- **Sizes** are estimated from the fix descriptions in a–h. The tests named below go red on trunk unless marked otherwise.

**Wave A: the recycle commit handshake (RC1).** Files: `scripts/handoff-fire.sh` (recycle sections only) and new `tests/handoff-recycle-*.bats` plus `tests/fixtures/move-lane-2026-10-18/`. About 180 LOC of code and 320 of tests.
- **K1 marker.** Write it after re-read 2 (`:18615`) and the debt, before `hf_exit_signal` (`:18629`) and `hf_exit_readback` (`:18646`).
- **The nudge.** With no marker, the nudge (`:11718-11746`) decides `precommit` and emits `recycle-nudge-precommit`. The clock `rcy_wait_t0` (`:11395`) starts at the marker. Every arm emits a row. The bgwork arm (`:11409+`) needs the marker.
- **K2 yields.** Add them at `:18595` and `:18603`.
- **`hf_recycle_hold`** (`:3615-3651`) writes `exit-aborted` and disarms *before* the slow unconfirm. Its line at `:3635` says "stays alive" only when `pane_cc_state` reads cc.
- **`hf_recycle_disarm`** (`:3341`) refuses to kill once the watcher's journal shows `CONFIRMED at a shell`, `type-attempt` or `bgwork@`, and emits `recycle-disarm-refused-committed`. This guards all 12 or more bare disarm sites.
- **The watcher's own bounds.** If the foreground is dead and there is no marker, it unconfirms from `$CMDFILE.confirmed` and exits. On `exit-aborted` it exits.
- **Hysteresis.** Add `HF_PRECHECK_LOAD_PER_CORE` (default 6) on the d58bb81d3 precheck.
- **Wording.** `hf_recycle_subject_yield` (`:3927`) says "exited before the commit", not "on its own".
- **Self-close watcher** (`:10692-10725`, retype via `hf_exit_readback` from 40 s on). Pin it with a test only.
- **Tests:**
  - `handoff-recycle-nudge-precommit.bats`: fake it2, empty composer, `pane_cc_state=cc`, no marker for 70 s. Assert 0 `/exit` sends. Then create the marker and assert exactly one gated retype.
  - `handoff-recycle-load-hold.bats`: the subject is killed inside a stubbed last read, at `HF_LOAD_PER_CORE=30`. Assert rc 0, a `recycle-subject-exited` row, no held-load row, and the watcher still alive.
  - `handoff-recycle-hold-after-watcher-commit.bats`: the journal says CONFIRMED. Assert no SIGTERM and no unconfirm.
  - A no-marker case where the foreground dies: assert the watcher unconfirms.
  - A pane-332 replay fixture: the watcher logs, `handoffs.jsonl:780-784,889-895` and the `history.jsonl` rows.
  - Keep `handoff-composer-gate.bats:250` as it is.

**Wave B: one admission decision and a durable queue (RC2).** Files: `scripts/lib/capacity-admit.sh`, `scripts/limit-recover/lr-handoff.sh`, `lr_recon/admit.py`, `lr-reset-poller.sh`, `bin/cc-pane-runner`. About 220 LOC of code and 280 of tests. Work in this order:
1. **Token redeem.** At `lr-handoff.sh:1536-1540`, the file path *is* the token whenever the file passes `_cc_admit_token_shape`.
2. **Orphan expiry.** `cc_capacity_tokens_inflight` (`capacity-admit.sh:1093-1125`) counts a token only while its spawn is pending. Bind `run=` at mint time; otherwise cap at 180 s.
3. **Token kind.** `admit.py:206` passes `CC_ADMIT_TOKEN_KIND=swap` for moves that owe no prompt.
4. **Budget.** The key carries the actor (`:576-582`). Queued requests get a time bound (`LR_CAPACITY_QUEUE_MAX_S` about 2700 s) instead of a count release (`:404-430`). The text at `:1637` drops "ADMITS".
5. **Poller.**
   - Autofire (`:2589-2603`) follows K5 and logs RESUMED only after `relaunch.rc`.
   - Requests with `cause:capacity` (`:1496-1625`) probe before any spawn. A refusal gives `REQUEST-STAY` with backoff min(60·2^k, 900) s and spends no attempt.
6. **Runner.** `cc-pane-runner:176-215` follows K3, with the exit record.
- **Tests:**
  - `lr-handoff-flags.bats:500-507` uses a real `cc_capacity_token_mint` output and asserts basis `token` and in-flight back at 0.
  - `cc-lr-request.bats`:
    - when the probe refuses, `spawn_resume` is never called;
    - when the probe admits, there is exactly one spawn and it carries `LR_ADMIT_TOKEN`;
    - when a live beat holder exists, nothing spawns (the 509e3aad replay).
  - `cc-pane-runner-exit75-closes.bats`:
    - rc 75 closes the pane, through the guard;
    - an in-place shell survives;
    - rc 1 with no record keeps the shell.
  - An actor-key case: the rescue's refusals do not release the poller.

**Wave C: lr-fire-resume's pane path and the composer classes (RC5, plus RC2's pane end).** Files: `scripts/limit-recover/lr-fire-resume.sh`, `scripts/lib/composer-intent.sh`. About 220 LOC of code and 300 of tests.
- **Refusal** (`:777-797`) follows K3: rc 75 plus the request. The three lines at `:789-791` become one line, and the knob comes from `CC_ADMIT_REFUSAL`'s term, not the hard-coded `CC_ADMIT_MAX_LOAD_PER_CORE`.
- **Delivery** (`:1555`, `:1584`) is one `send -- "\033\[200~$prompt_b\033\[201~"`, with the CR gated separately. Above about 800 characters, type a pointer line instead of flattening (`:807`).
- **No-token runs** mint `run:<sid8>:<UTC>:<hex>` (`:826-840`). `skip` at `:1665` must not break before the look and re-CR loop, and the run ends in an explicit UNSUBMITTED through `lr_tell`. Add a fallback run dir so `:1132` and `:1148` log.
- **Reader** (`:1113-1125`) strips all leading chips. `LR_SCREEN_SH` (`:1033`, `:1079`) reads with `--ansi` and drops SGR-2 runs, as `cc-tui.sh:239` does.
- **Worktree argument** (`:39`) must be absolute with no control characters. Do not add `-d`, because `:653-690` restores missing worktrees.
- **Shell banner** (`:1859-1870`): print "ordinary shell" only when nothing follows.
- **Composer classes.** `composer-intent.sh:45-80` gets `rail-exit` for an exact `/exit`. `:64-66` accepts multiple chips as `rail-token`. Add `rail-residue` for a byte match of the last recorded residue.
- **Tests:**
  - `lr-fire-resume-screen-multichip.bats`: the 430 box reads DRAFT-MINE.
  - `lr-fire-resume-inject-atomic.bats`: a pty child logs its reads. Assert one `200~`/`201~` pair, with the CR in a later read.
  - `lr-fire-resume-no-token.bats`: a token is minted, a re-CR is sent, and the verdict is non-green.
  - `lr-fire-resume-capacity-queue.bats`:
    - rc 75;
    - still exactly 1 request after 3 re-runs, with `first_refused_at` unchanged;
    - no "re-run this exact command";
    - with `LR_RUN_DIR` set: rc 9 and no request.
  - `composer-intent.bats`: `/exit` gives rail-exit, two chips plus a token give rail-token, and a dim-suggestion fixture reads EMPTY.

**Wave D: placement policy outside handoff-fire (RC3), and keystroke provenance.** Files: new `scripts/lib/pane-placement.sh`, `scripts/limit-recover/lr-lib.sh`, `bin/cc-relayout`, `bin/it2-kitty`, `hooks/validate-bash.sh`, `config/kitty.conf`, `commands/handoff.md`, `bin/cc-where`. About 260 LOC of code and 220 of tests.
- **`cc_place_pane <anchor> <cwd> -- <argv>`** chooses, in order:
  1. a vsplit into the anchor's OS window, if it has 1 tab and fewer than `CC_MAX_PANES_PER_SPACE` (4) panes;
  2. otherwise the next operator OS window with room;
  3. otherwise a new `--type=os-window --os-window-state=fullscreen --keep-focus`.

  Split retries are bounded and scale with load, which answers "splits time out". Every spawn is logged with requested and given.
- **`lr_kitty_spawn`** (`lr-lib.sh:1286-1313`; the os-window branch is `:1296-1299`) calls it. This is what made 428, 429 and 398 single-pane windows.
- **`cc-relayout:363`**: its tab placeholder becomes a fullscreen os-window. This is a deliberate behaviour change and gets its own test.
- **`it2-kitty`**:
  - refuses `--type=tab` (rc 2) unless `CC_ALLOW_TAB=1`, which only `cc-resume-layout.sh:946` sets;
  - writes every `send`/`send-text` to `~/.claude/logs/pane-keys.jsonl` as `{ts, pane, caller, sid, sha256, head40}`.
- **`validate-bash.sh`** (near `:492-564`) denies agent Bash that:
  - launches a tab (`--type=tab`, `new_tab`);
  - runs `handoff-fire … --tab` or `--launcher /tmp/`;
  - loads a LaunchAgent plist that lives outside the repo.
- **`kitty.conf:930`**: `cmd+t` per Q4.
- **`handoff.md:500-575`**: drop the `--tab` doctrine. Rescues use `lr-fleet --one` or `cc-lr recover`.
- **`cc-where:360`**: alert on any OS window with more than 1 tab or more than 4 panes.
- **Tests:**
  - `pane-placement.bats`, with a stub kitty serving a mutable `ls`:
    - 3 panes give a vsplit;
    - 4 panes give a fullscreen os-window;
    - a replay of 16 fires gives 4 windows, each with 1 tab and at most 4 panes.
  - `it2-kitty-no-tab.bats`.
  - New `validate-bash` deny cases.
  - A pane-spawns ratchet: bg-tab rows equal 0. It would have read 22 overnight.

**Wave F: truthful pane verdicts and a closer that can close (RC4).** Files: `hooks/lead-crash-watchdog.sh`, `bin/cc-pane-close`, `bin/cc-husk-sweep`. About 200 LOC of code and 220 of tests. It uses the K3 exit-record schema, not B's code.
- **Watchdog** (`:1665-1793`):
  - join the lr facts: `locks/`, bundle `events.jsonl`, `faults/<sid>.json` and `*.HANDOFF.json`;
  - on STRANDED, paint `✗ <sid8> moved <src>→<dst>, relaunch failed · ▶ lr-fleet --one <sid8>` and enqueue it;
  - paint after the closer's predicate (`:1790`, `:1793`);
  - build the resume hint from the store that holds the full transcript (`:1674`).
- **`cc-pane-close`** gains:
  - a never-launched arm, driven by the exit record;
  - a transcript reader that follows `HANDOFF.json` across stores;
  - custody "moved, with a LIVE copy" (K6);
  - a guard check before closing a last pane.
- **`cc-husk-sweep`** checks HANDOFF-RECYCLE markers and successor claims before it says RESUME.
- **Tests:**
  - `lead-crash-pane-verdict.bats`: a STRANDED bundle shows no "CLOSED CLEANLY" and no "safe to close", and the hint is `claude3`.
  - `cc-pane-close-never-launched.bats`: rc 9 with no start closes through the guard, and a tombstone without a LIVE copy is refused.
  - `cc-husk-sweep-lineage.bats`.

**Wave G: lane coordination and an honest census (RC6, plus RC7's drain).** Files: `lr-move-worker.sh`, `bin/cc-lr`, `lr-upgrade.sh`, `lr_recon/act.py` plus its cohort module (not `admit.py`), and new `scripts/checks/launchagent-provenance.sh`. About 220 LOC of code and 240 of tests. Rebase `bin/cc-lr` on 11b063908 first.
- **One driver per session.** The reconciler assign (`act.py:86-87`) takes `runs/by-sid/<sid>.active` before the token.
- **Cohort exit.** A member whose source account is under its caps, or past its reset, goes NOT_NEEDED and is resumed in place.
- **Census.** `cc-lr:1272` and `lr-upgrade.sh:746`, `:1080` call `pane_bgwork_dialog` and produce `bg-work-dialog`, which means hold plus one page. `lr-upgrade.sh:2215` maps bgwork to hold.
- **Move worker.** At `:239-256`, `rail-exit` gets `cc_tui_clear` and is never carried. At `:143-162`, a wait that never changes for the whole budget pages once.
- **Drain.** Fold the drain's behaviour into `lr_recon` with a reset-aware "capped" that stops after rc=1. A provenance check pages on any `com.reso.*` LaunchAgent the repo did not ship.
- **Tests:**
  - two `lr-handoff` runs on one session 2 s apart: the second gets claim-held;
  - cohort expiry;
  - the `bgwork-dialog-2.1.284.txt` screen gives hold;
  - an `/exit` composer is cleared, not carried;
  - a stray plist pages.

**Wave H: one renderer and the Stop readout (RC8).** Files: new `lib/cc-say.sh` and `lib/cc_say.py`, `hooks/operator-readout.sh`, `lib/config-mirror.zsh`, `lr-preseed-env.sh`, `bin/cc-close-attrib`, `bin/cc-lid`, `scripts/kitty-setup.sh`, `hooks/session-index-end.sh`. About 380 LOC of code and 300 of tests.
- **`cc_say KIND VERDICT [FACT] [ACTION]`** prints one line: `glyph verdict · fact · ▶ cmd`. It fits in 56 cells or fewer, uses truecolor, and never uses SGR-2. Detail goes to `~/.claude/logs/pane-say.jsonl`.
- **Readout.**
  - Q2: `:1366-1374` gets a lower bound at NOW, and an overdue item reads "overdue · nothing fired".
  - The header is about this session only (`:1504-1523`).
  - The standing piles collapse to one footer row.
  - Rows are 52 cells or fewer.
  - The hash covers the semantic rows only (`:2167`).
- **Other producers:**
  - `config-mirror` and `lr-preseed` go to the log only;
  - `cc-close-attrib` `:501`, `:596` and `:599` become one line each;
  - SGR-2 is removed at `cc-lid:127` and `kitty-setup.sh:158`;
  - `session-index-end.sh:60` queues the row on SQLITE_BUSY.
- **Tests:**
  - `cc-say.bats`, under bash 3.2 and zsh:
    - 1 line per call;
    - 0 `\e[2m`;
    - within width at 37, 45 and 57 columns;
    - command bytes left plain.
  - `operator-readout.bats` fixture:
    - 7 rows or fewer, each 52 cells or fewer;
    - no pile count in row 1;
    - an overdue class-B row is not shown as "≤24h".
  - Update the pinned-string tests (10 + 7 + 5 + 4 files).

**Wave E (tier 2, the same file as A, so serial): the handoff-fire fire and surface path (RC3, RC7).** Files: `scripts/handoff-fire.sh` (fire and spawn sections). About 240 LOC of code and 300 of tests.
- **Retire tabs.**
  - `--tab` (`:14535`) becomes a deprecated alias that goes through `cc_place_pane`;
  - delete `:15195-15197`;
  - `:17615-17638` and `:18133-18151` place through the policy;
  - `:18215` becomes fullscreen;
  - the room check covers named anchors (`:18282`, `:18319`);
  - `kt_launch` (`:1595`) refuses `--type=tab`;
  - rewrite the help (`:108-149`) and the dead advisory (`:19356-19361`).
- **Validate the cwd.** `--cwd`, `--resume-cwd` and `SP_CWD` (`:14529`, `:14559`, `:12780`) must be absolute, free of control characters and existing; otherwise exit 2 before any gate. Assert at `:17233-17238` too.
- **See a failed launch.** `FIRE_PARKED_RE` (`:5790`) matches `zsh:cd:1:` and `exited <rc>`. The PARKED verdict (`:19890-19905`) reads the exit record.
- **Wall clock** in `verify_engagement` (`:6279`, `:6339`, `:7501`).
- **Admit before spawn.** For `--launcher …lr-fire-resume…`, run `cc_capacity_admit` before `spawn()` and mint `LR_ADMIT_TOKEN`. The fire budget is keyed per subject (`:9975-9980`).
- **Refuse `--launcher /tmp/*`** for a session that has a STRANDED record.
- **Tests:**
  - `handoff-fire-no-tab.bats`: the recorded argv never contains `--type=tab`, and the 16-fire replay gives 4 windows.
  - `handoff-fire-cwd-validate.bats`: `$'whose\n/tmp'`, a relative path and a nonexistent path each exit 2, and no spawn row is written.
  - `handoff-fire-pane-parked.bats`: the literal 403 screen.
  - A stub admit rc 9 gives 0 `kitty @ launch` calls.
  - The in-pane IDL basis is `token`.

**Wave H2 (tier 2): move the remaining producers onto `cc_say`.** Files: `bin/cc-pane-runner` (`:310` echo, after checking the probes at `:383-385`, plus the exit lines), the `lr-fire-resume.sh` preflight (`:370` and the rest), the watchdog's `pane_verdict_text` bodies, `bin/cc-lr` move output (`:1422` bounds), and `capacity-admit.sh` (add `cc_capacity_admit_short`). About 250 LOC of code and 200 of tests. Test: `pane-husk-screen.bats` replays pane 435 and asserts:
- 2 lines or fewer, the first starting with `✗` and naming the sid8;
- a `▶` command of 40 characters or fewer;
- that command, run with `--dry-run`, does not refuse.

**Wave S (tier 3): a keystroke-free move lane.** Files: `handoff-fire.sh:4532-4558`, `lib/pane-successor.sh`, `lr-fire-resume.sh:1830-1858`, `bin/reso-resume-one`, `bin/cc-close-attrib`. About 260 LOC of code and 260 of tests.
- Stage a successor for transplant and resume recycles, and run the fold and launch-lock rails when the successor is claimed.
- `hf_exit_signal` (`:3795+`, which needs a staged successor at `:3869-3871`) then replaces the typed `/exit`, and the load hold no longer applies.
- Test: a move replay at a stubbed 30/core gives 0 typed keys and MOVED.
- This interacts with Q3, because SIGTERM stops background tasks.

**Wave B2 (tier 3): a better admission signal.** Count CPU-active turns and set the ceiling in cores (`capacity-admit.sh` plus a sampler writing `~/.claude/autonomy/active-cpu.json`). About 160 LOC of code and 150 of tests. Test: sessions blocked in `sleep` do not count.

## 5. Open questions for the operator

1. **Which pane is image #1?** a says pane 332; g-adversarial says pane 1. The mechanism is the same (RC1) either way. Conviction 55% that it is pane 332. Matching the screen text settles it.
2. **The drain LaunchAgent: pause it now (recommended, 90%), unload it, or keep it once Wave G makes it reset-aware?** Account 1 is at 2/22 and account 4 at 2/5, while next3 is the hottest at 53/36. The "drain 1 and 4" premise no longer holds.
3. **What may a recycle kill when the session has background tasks?** The options:
   - (i) never move a session with a background job; the census already waits on `wait:background-job`;
   - (ii) "Exit and stop tasks", which is today's watcher behaviour;
   - (iii) "Move to background and exit".

   Recommended: (i) for moves, and (ii) only when the sole job is `cc-await-ping`. Conviction 75%.
4. **When the 4-pane windows are full: open a new fullscreen OS window on its own Space (recommended, 70%), or queue the fire until a slot frees?** Also decide what `cmd+t` should do: open a new OS window, or be unmapped.
5. **Pane 430 (e52f1f63) is waiting on your answer** (661a8652d2f6): answer it, or retire the session with `self-close --terminal`.
6. **Pane 258 (9f6593c5) has been idle for 7 days** (decision 56c6862291f2): close it, start a replacement beside it, or keep it. Conviction 65% that you should close it after a transcript check.
7. **Was account 2 really capped before 09:00Z?** 5232121f hit "weekly limit" 5 s after it swapped onto next2, while utilization showed 0/0. If it was capped, every move to account 2 before 09:00Z was futile, and the router needs a per-account rejection fact. Conviction 50%. Your usage page settles it.
8. **The class-B defaults were due at 05:00Z and never auto-fired.** They were actioned by hand at 17:13Z. Was that intended (the veto window is advisory), or is the actuator broken? Conviction 60% that it is broken.
   - CORRECTED (2026-10-18): **broken, 95%, and nobody actioned them by hand** (`q8-classb-actuator.md`). The actuator is §2 of `scripts/autonomy-sweep.sh` (:1185-1233, launchd every 300 s). 39 of 40 runs between 05:00Z and 17:13Z hit the sweep's 400 s limit before §2. The 17:13Z run reached it at 399 s and fired all three, 12 h 13 min late, then stopped before notifying the desk. Fix (owned by Wave H): run §2 right after `strand_rung` (:536).
9. **Agent autonomy.** Should lead sessions ever be allowed to install LaunchAgents or `/tmp` launchers? Recommended: deny both (Waves D and G), conviction 85%. The registry inversion (`cc-registry` rows exist for closed panes but not for live 19, 27 and 28) also needs an owner.

**Confidence in this synthesis: 85%.**
- The highest-confidence root causes are RC1 (live repeat), RC2 and RC4: each was measured in logs, screens and code, and survived adversarial passes.
- RC5's lost Enter is the weakest item at 50%. Wave C's capture would settle it.
- RC8 (65%) and RC9 (70%) rest on single snapshots.
- What would lower this: a second `/exit` sender found in the new `pane-keys.jsonl` once Wave D lands, or a replay showing that Wave A's marker does not stop the 60 s send.