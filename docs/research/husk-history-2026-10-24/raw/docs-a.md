# Husk history, docs slice A (read-only)

Written 2026-10-24 by a read-only worker. Scope: 11 research docs (listed in the brief), what each
asked, which cause it named, what it prescribed, which commit implemented it, and whether a later
doc or log shows the symptom again. Nothing was edited except this file.

How the data was gathered:
- Each doc was read in full with `cat -n`.
- Doc shas come from `git log -- docs/research/<doc>`.
- Implementation shas come from `git log --grep` (husk, pane-close, pane-verdict, self-close,
  reap-guard and similar terms), plus `git show -s` for commit bodies.
- Incident rows for pane 289 come from `rg 7555024a ~/.claude/logs/{pane-close,pane-say}.jsonl`.

Every count below is either **measured** (the command is named) or quoted from the cited doc.

## Chronological table

| when | source | what was asked / claimed | root cause named | change (sha) | recurred? |
|---|---|---|---|---|---|
| 2026-08-04 | `docs/research/kitty-selfclose-chain-2026-08-04.md` (docs e46de0942, c3951fdb2) | Why do Agent-Team assignee panes never close in kitty? It reports 231 SURFACE lines all-time and 0 closes (`:99`). | (1) **The per-member attribution verdict is thrown away, and the next gate re-asks a whole-tree question on a shared cwd.** `scripts/reap-guard.sh:118` reads the whole `git status --porcelain`, so one untracked file the *lead* wrote blocked 12 assignees (`:70-80`, L7). (2) The shared-cwd arm swallows every non-zero exit (L8, `:99`). (3) A `<teammate-message>` shutdown_request counts as operator adoption (L9). (4) **C3: `bin/cc-pane-runner:115` `_fallback` execs an interactive login shell, so even a perfect exit leaves an open window. External close-window is mandatory** (`:51-56`). (5) The `it2-kitty` close checks only that the id is digits, not who owns it (L13). | Prescribed (`:123-149`): `--tree-scope shared` and `--tree-verdict`; on a shared cwd, ask only about the member's own dirt ("Every other tree-cleanliness question is **deleted on a shared cwd**", `:119`); an identity pin; a residency alarm (§5). **Implemented: 5cd17f5da** (2026-08-04, "gate the pane close on own-footprint dirt, not the lead's whole tree"). `rg tree-scope scripts/reap-guard.sh` shows it is live at `:14,:33`. Follow-up 02dd6ae3c (2026-09-30, a read-only member closes on a shared cwd). | **Yes, and the root cause itself came back.** Teammate husks returned on 09-30 (panes 33/57/58/59/60, `husk-panes-2026-09-30.md:15-19`). The whole-cwd dirt gate this doc deleted was re-created in a new closer: **`bin/cc-pane-close` gate 4 (d150099dd, 2026-10-01) "no uncommitted work in the session's cwd"**. On its first dry run it already refused pane 76 "while its cwd held an uncommitted file", which was the lead's shared cwd (d150099dd body). It is now at `bin/cc-pane-close:508-512`, with no own-footprint attribution: `rg session_dirty_mine\|allow.dirty bin/cc-pane-close` returns 0 hits. Pane 289 on 2026-10-24 hit exactly this. |
| 2026-08-25 (doc dated 08-26) | `docs/research/recycle-pane-survivability-2026-08-26.md` (c67bda626, 25862d6af) | Pane 32's `--recycle` typed `/exit`, the pane vanished, and nothing reported it for 10 min (`:7-10`). | The pane's argv **was** the launcher (`kitty @ launch -- reso-resume-one` → `exec expect`), with no shell under it, so `/exit` destroyed the window. The watcher's only sensor was the dead tty (`:33-59`). | Prescribed and **implemented in c67bda626** (2026-08-25): `reso-resume-one` execs `${SHELL} -l -i` after expect; a `pane_shell_root` survivability gate; a `pane_enumerated` vanished arm. Audit and pin: 25862d6af (2026-09-04). The stated invariant: "**Any pane an agent may later be asked to recycle must end its command with an interactive shell**" (`:142`). | **It caused the opposite symptom.** This invariant is why every intended close now needs an external closer. `selfclose-failures-2026-10-01.md:31` shows pane 10 left at a shell by `reso-resume-one:712`. That was reversed for clean exits by 6347b1731 (2026-10-01, "a resumed session that exits cleanly closes its pane instead of leaving a husk") and fbbf04784 (2026-10-02). Since 265790f36 (2026-10-15), the fullscreen guard can veto that close-on-exit. |
| 2026-09-04 | `docs/research/husk-panes-pkill-selection-2026-09-04.md` (736632a95, 570c20375, c68525b6e) | Five panes (144/290/296/297/298) sat at a bare shell. The operator read them as failed self-recycles. | It was not a recycle. A sibling session's `pkill -f "cc-await-ping"` matched every fired peer, because the brief lives in argv. The guard was keyed on how the command was spelled, not on what it would select (`:7-20, :52-63`). The doc names this a 3rd recurrence: 08-09 and 08-25 came before. | **Implemented**: a selection-keyed kill gate, `hooks/lib/kill-selection.py` (736632a95); `cc-await-ping --stand-down`; **`bin/cc-husk-sweep`** (570c20375), the recovery half. Explicit policy: "**The husk panes themselves are not closed by anything** … the recovery affordance" (`:101-103`). | **Yes, several times.** desk-husk 09-08 (a group SIGTERM, sender never identified). 09-30 pane 55: devserver-gc matched a brief in argv (fixed in 5a673c141, `husk-panes-2026-09-30.md:27`). **`husk-mass-sigterm-2026-10-21.md`**: 9 husks from `pkill -f "next start" -P …`, "the guard built for exactly that shape missed it". Further guard patches: f6d2418b4 (10-21, a quote spanning lines hid a pkill) and 7fe2ccc90 (10-23, stand-down signals only real cc-await-ping processes). |
| 2026-09-08 | `docs/research/desk-husk-2026-09-08.md` (810ee9be3) | Desk `88e2c2b1` (pane 330) died at a prompt that looked exactly like a clean exit. | An external SIGTERM hit the whole process group; the sender was not identified (`:9, :66-68`). The banner was ambiguous, and nothing painted a verdict. The death page went to the dead desk's own inbox. cc-husk-sweep runs only when typed by hand. desk-invariant was disabled (`:73-87`). | **Implemented 810ee9be3**: lead-crash-watchdog writes a verdict block onto the tty (`⛔ NOT A CLEAN EXIT … KILLED` / `✅ CLOSED CLEANLY`) and escalates when the victim is the desk; husk-sweep excludes live sids. **Left open on purpose**: "`cc-husk-sweep` still verdicts RESUME on a dirty cwd even when the dirt predates the session (pane 330's 22 dirty paths are older than the desk)" (`:117-119`). | **Yes. That open item is pane 289's false ⛔.** Painted banners went stale or false: 09-30 defects 6 and 7 (a retired teammate painted KILLED; the close-verdict reader contaminated by CLAUDE.md text, `husk-panes-2026-09-30.md:32-33`); `husk-panes-2026-10-22/REPORT.md` ("a pane's end state has no owner … its screen shows whatever the last writer believed"). On 2026-10-24, `pane-say.jsonl` (**measured**, `rg 7555024a`, 5 rows) shows `cc-pane-verdict` painting `"⛔ resume 7555024a"`, `"✗ 7555024a stopped mid-task · 138 unsaved files"`. |
| 2026-09-30 | `docs/research/selfrecycle-agentview-off-2026-09-30/README.md` (249a16fad) | The W5b2 session (pane 38) self-recycled twice; `/exit` raised "Background work is running", the watcher answered Stay, and nothing relaunched (`:3-7`). | The dialog counts the recycle's own foreground Bash call as a `shell` task, so every self-recycle raises it (`:48-50`). | **Implemented 249a16fad**: wait for the call to return, then Esc, then `/exit`. | **Yes, in a sibling form.** `lr-stranded-husk-2026-10-10/ROOT-CAUSE.md`: pane 168's `/exit` raised the dialog and was answered "Move to background and exit", leaving a stranded husk. Fixed by 22df298c6 (10-10) and 99601cdd8 (10-03, the self-close variant). |
| 2026-09-30 → 10-01 (3 rounds) | `docs/research/husk-panes-2026-09-30.md` (55a2a049e, 38dd029e6, 2dcfbe739) | After the reboot, 7 of 39 kitty windows were husks. The operator contract: a recycle resumes in the same pane, a close closes the pane, and "a pane left at a bare shell … is a defect in either case" (`:5`). | "**Nothing closes a pane from inside after Claude exits**" (`:9`). Every close depends on kitty remote control, which was intermittently deaf (round 3: the talk thread exits for good on an `accept()` error, `:84-96`). Teammate closers make one attempt each with no retry. Self-close aborted on an unreachable kitty. The watchdog painted a retired teammate as KILLED. The close-verdict reader was contaminated. cc-husk-sweep named the wrong sid, account and cwd. | **Implemented**: F-e 476712b2f; F-b 7eb551b39, f57055245, 3156c4dcd, aa1e2deb5, 107755b5b; **F-a 74baff1ee** (a clean claude exit closes the pane); F-c b6bf10c0c; F-d bbc40d207; devserver-gc 5a673c141. Round 2: 8eaa04358 (backgrounded Bash counts as in flight); **d150099dd `bin/cc-pane-close`**, whose 4 fail-closed gates include "**no uncommitted work in the session's cwd**"; bd39fb7c7; b6727f1d9. The upstream kitty `accept_peer` fix was named, not made. | **Yes.** `lr-wake-incident-2026-10-18/c-husk-panes.md` (17 husks); `husk-mass-sigterm-2026-10-21.md` (9); `husk-panes-2026-10-22/REPORT.md` (85/42/101); pane 289 on 2026-10-24. **Measured**: `rg -c 7555024a ~/.claude/logs/pane-close.jsonl` gives 9 rows, every one `refused … /Users/chrisren/Development/personal holds 138 uncommitted change(s)`, from 2026-10-25T00:00:13Z to 01:33:14Z. The brief's "21+" was not reproduced from this log; other refusals may sit in other logs. |
| 2026-10-01 | `docs/research/husk-triage-2026-10-01.md` (979c46927) | Triage of panes 55, 69 and 76 (close or resume?), and gaps in the F-a..F-d branches. | F-a misses teammate panes: the launch line is `cd … && env … claude.exe --agent-id`, so the first word is `cd` (`:41-51`). F-c: a killed lead whose work was later collected still paints "Resume it here" (`:55-60`). F-d: UNKNOWN is resumed, and no custody is read (`:68-70`). | **Implemented**: the F-a verb parse was folded into 74baff1ee (its body: "The verb is the LAUNCHER, not the first word"); e44823f02 (watchdog: a lead whose work was collected is never offered `--resume`); 904fdd205 (husk-sweep: collected is never resumed). | **Yes, the same contradiction.** Pane 289: cc-husk-sweep reads COLLECTED / close (per the brief), while cc-pane-verdict `--recompute` (`bin/cc-pane-verdict:86-87`) maps the closer's `"uncommitted change"` text to `STATE=RESUME`. Two readers apply two policies to one pane. |
| 2026-10-01 | `docs/research/selfclose-failures-2026-10-01.md` (979c46927) | Why did panes told to self-close stay open? Over 7 days: 199 invocations, 151 physical closes, 0 failed (`:14`). | M1: a stale kitty-id stamp refuses genuine peers. M2: a deaf terminal is read as UNREACHABLE. M9: a stranger's stamp gives a false pass. M10: closedAt and custody are written before the abort. M11: a duplicate fire. **M5: a dirty tree refuses, classed as "Intended (protects unsaved work)"** (`:22`). `/exit` by hand leaves a shell (`:31`). | **Implemented**: eee5cf8c5 (stale or stranger stamp); 4fad69e1d and eed8bf399 (closedAt and custody only after proof); 6347b1731 (reso-resume-one closes on a clean exit); 5c3905fcd (09-30, a kitty fire never reports its own launch as failed). Later: af6c54c8d (stamps carry their kitty generation), 64513d5e1, aea01028e (self-close closes only its own pane), d82aa7860 (a pane self-close cannot close is handed to the pane closer). | **Yes.** Stamp or ownership errors recurred: on 10-22 pane 85's self-close closed the lead's pane 16 (`husk-panes-2026-10-22/REPORT.md:26`). The M5 dirt gate is honoured *upstream*: 7555024a passed `--allow-dirty`. Since d82aa7860 (10-22), a refused self-close hands off to `cc-pane-close`, which has no allow-dirty or own-footprint input and re-refuses on the same dirt. |
| 2026-10-01 | `docs/research/recycle-unreachable-2026-10-01.md` (ea9055e32) | Pane 19's recycle aborted ("resolver CANNOT TELL"). | A real, intermittent outage of kitty's remote control: kitty at PRI 4 (the background band) under load 120-250 (`:7-12`). F-b's wait and retry applied to self-close only (`:63`). | Prescribed: a detached wait on the resolver; resolve the tty from process ancestry; `NSAppSleepDisabled`; per-phase timing. **Implemented**: e66bf5760 (a recycle on a deaf kitty is held in seconds, timed and owed durably); 7fe0e98af (an owed recycle is re-run); 0b3fb8bc5 (10-20, the resolver's connect timeout is retried). | **Yes, kitty deafness persists.** It is a standing theme in `lr-sustained-load-2026-10-20/impl/B5-kitty-off-critical-path.md` (path from `rg -l`), and the 10-18 lr-wake incident had 17 husks. `bin/cc-pane-verdict:76` still has a "kitty didn't answer" arm. |
| 2026-10-01 | `docs/research/w7e-recycle-dead-2026-10-01.md` (bb3345f20, 75642a817) | `recycle-dead` paged over sessions that were answering (panes 18, 33, 28). | A token gate: the oracle needs the run token, which never arrives when the launcher refuses to type. "12 / 16" of the pages were false (`:66-72`). | **Implemented f5890107e** (2026-10-01, "a resume answering on its target is not a dead recycle"). | Not a husk recurrence as such. It is an instance of the *verdict readers disagree with reality* pattern, the same as the false ⛔ on pane 289. |
| 2026-10-01 | `docs/research/kitty-quit-research-2026-10-01.md` (27943940b) | How to restart a wedged kitty 610 (remote control dead, 59 zombies) without the quit dialog. | The talk thread is gone and SIGCHLD goes unprocessed. The `osascript`/⌘Q quit raises a confirm dialog (`:8-27, :47-62`). | A TERM → 10 s → KILL script, then `open -n` with a scrubbed environment (§5). "No step here was executed" (`:~229`). Preserved in 27943940b; staged patched kitty aedb5b64f (09-30). | **Indirectly.** `kitty-crash-2026-10-15/README.md` led to **the fullscreen guard** (fb3edd4ff, 62372906a, 265790f36), then **rc 70 on a refused-fs close** (1211646fb, 10-16). That guard is the new refusal class that stopped pane 289's self-close (rc 70) before the dirt gate refused the fallback. |

## Pane 289 traced through this slice's history

The chain below is built from commit bodies and `bin/` reads. The incident facts come from the brief
and `~/.claude/logs`.

1. **The self-close is refused with rc 70.** The fullscreen guard (265790f36, 62372906a; exit code 70
   from 1211646fb) refuses because the pane is the last pane of a native-fullscreen window. That guard
   was added after `kitty-crash-2026-10-15`, two weeks after F-a (74baff1ee) made close-from-inside the
   cure.
2. **The refusal is handed to `bin/cc-pane-close`.** Since d82aa7860 (10-22), a refused self-close is
   passed to the pane closer through a husk row and the drainer (5d0be0366, 4cb749ceb).
3. **The closer refuses on dirt that is not the session's.** Gate 4 (`bin/cc-pane-close:508-512`,
   unchanged in logic since d150099dd) counts *all* porcelain lines in the cwd: 138 sibling files.
   That repeats the 08-04 L7 defect (whole-tree dirt on a shared tree) that 5cd17f5da fixed only
   inside `reap-guard`. The session's own `--allow-dirty` judgment and its "Good to close: yes" are
   not passed through. This is the same "verdict thrown away before the gate that actually blocks"
   pattern the 08-04 doc convicted (`kitty-selfclose-chain-2026-08-04.md:70`).
4. **The refusal is painted as RESUME.** `bin/cc-pane-verdict --recompute` turns
   `*"uncommitted change"*` into `STATE=RESUME` (`:86-87`). That is the 09-08 open item ("RESUME on a
   dirty cwd even when the dirt predates the session", `desk-husk-2026-09-08.md:117-119`), now inside
   a single writer (99acf1d9f).

## Husk-related docs outside this slice

These are from `rg -l -i husk docs` (**measured**: 229 files). The docs-b slice is not known to this
worker, so this lists every doc whose title or headline is primarily about husks or pane end-of-life.
Lower-signal mentions (lr100p, lr-detect, token-efficiency dossiers and others) are omitted.

- `docs/research/husk-panes-2026-10-22/` (REPORT.md, synthesis.md, skeptics.md, investigators.md, a7-sigterm.md, round2-2026-10-23/{investigators,skeptics,synthesis}.md)
- `docs/research/husk-mass-sigterm-2026-10-21.md`
- `docs/research/lr-stranded-husk-2026-10-10/` (REPORT.md, ROOT-CAUSE.md, round2/C1..C6, M2)
- `docs/research/lr-wake-incident-2026-10-18/c-husk-panes.md` (+ REPORT.md, a-failed-self-recycle.md, h-live-remediation-findings.md, z-critic.md)
- `docs/research/kitty-crash-2026-10-15/README.md` (the fullscreen guard's origin)
- `docs/research/close-verdict-first-2026-10-10/` (REPORT.md, design.md, slot-ledger.md, slot-docs.md, skeptic-false-fail.md)
- `docs/research/close-behavior-2026-10-18/axes/10-detector-design.md`, `round2/C5-rule-text.judge-impl.md`, `round2/C6-doc-disposition-marker.judge-fp.md`
- `docs/research/recycle-failures-kitty-2026-10-10/` (skeptic-f2-f4-exit-residue.md, slot-f3-defer-watcher.md, slot-primitive.md)
- `docs/research/teammate-resurrection-2026-10-16/` (REPORT.md, slots/*)
- `docs/research/teammate-teardown-verdict-2026-10-10/` (01-arm-mechanics.md, 04-contract-and-skill.md, 05-design-and-control.md)
- `docs/research/sigterm-forensics-2026-08-25.md`
- `docs/research/inboot-resume-research-2026-10-01.md`
- `docs/research/session-durability-2026-10/` (C1..C5)
- `docs/research/lr-sustained-load-2026-10-20/impl/B5-kitty-off-critical-path.md`, `G2-self-recovery.md`
- `docs/research/subagent-lifecycle-2026-09-19/E-fleet-transport-it2-kitty-runner.md`
- `docs/research/SESSION_CLOSE_AND_LAG_2026-07-26.md`, `docs/research/RESTART-BRIEF-2026-07-27.md`, `docs/research/iterm2-freeze-30-sessions-2026-07-30.md`
- Plans: `docs/plans/pane-end-of-life-2026-10-22.md`, `docs/plans/pane-lifecycle-fixes-2026-10-01.md`, `docs/plans/HANDOFF_FAILURE_DETECTION_V2.md`, `docs/plans/LIMIT_RECOVER_FLEET_V2.md`, `docs/plans/LR_INPLACE_IMMEDIACY.md`, `docs/plans/LR_SUSTAINED_LOAD_IMPL.md`, `docs/plans/PANE_THEFT_2026-08-07.md`
- Proposal: `docs/proposals/ARMED_SUCCESSION_LIFECYCLE.md`
- Lessons: `docs/lessons/launcher-runs-the-live-layer.md`, `docs/lessons/remote-pane-identity-is-the-targets-not-the-drivers.md`, `docs/lessons/two-causes-one-rc-ask-a-lower-layer.md`
- Index: `docs/research/INDEX.jsonl`

## Why it keeps coming back (evidence-backed)

1. **By design, a pane's resting state is "shell kept".** `cc-pane-runner` `_fallback`
   (`kitty-selfclose-chain-2026-08-04.md:51-56`) and the 08-26 invariant ("must end its command with
   an interactive shell", `recycle-pane-survivability-2026-08-26.md:142`) make the shell the default
   after any exit. The 09-04 policy ("husk panes are not closed by anything … recovery affordance")
   adds to that. So every intended close needs a second actor to undo the default, and each
   independent veto (fullscreen guard, deaf kitty, dirt gate, identity gate) re-creates a husk. F-a
   (74baff1ee) flipped the default for clean exits, but later guards (265790f36) added vetoes that
   restore the shell.
2. **A defect fixed in one gate is re-created in the next closer.** The 08-04 doc convicted
   "whole-tree dirt on a shared cwd" and "the attribution verdict thrown away before the blocking
   gate". It fixed this only inside reap-guard (5cd17f5da). d150099dd (10-01) built `cc-pane-close`
   with gate 4 asking the same whole-cwd question again, and refused pane 76 for it on day one. No
   shared library or test carries the rule "gate on own footprint" across closers.
3. **Known gaps were written down and left open.** desk-husk 09-08 recorded that RESUME-on-dirty-cwd
   misclassifies pre-existing dirt (`:117-119`). That reading is now built into `cc-pane-verdict`
   (`:86-87`) and painted pane 289 as "stopped mid-task · 138 unsaved files".
4. **Several readers apply several policies to one pane.** cc-husk-sweep (COLLECTED), cc-pane-close
   (refused: dirty), cc-pane-verdict (RESUME), the watchdog and the self-close path each classify the
   same pane separately. The 09-30 doc (defects 6-8), triage 10-01 and the 10-22 REPORT ("end state
   has no owner") each fixed one reader; 99acf1d9f consolidated the painter but not the decision.
5. **Fixes are keyed on the last incident's spelling, not the class.** The pkill guard was patched
   five times (08-09, 08-25, 736632a95 on 09-04, f6d2418b4 and 7fe2ccc90 in October) and still missed
   10-21. Each husk round lists new defects the previous wave "had not covered"
   (`husk-panes-2026-09-30.md:65`).
6. **New safety guards add refusal classes that end in a husk.** The fullscreen guard (10-15), rc 70
   (10-16), the identity pin and the composer guard each turn a close into a kept shell when they
   refuse. The design treats a kept shell as the safe outcome (fail-closed), so every added guard
   raises the husk rate unless its refusal also has an owner that finishes the close.
7. **The external dependency is unreliable.** Kitty remote control goes deaf under load, and its talk
   thread can die (`husk-panes-2026-09-30.md:84-96`, `recycle-unreachable-2026-10-01.md:7-12`). The
   upstream one-line fix was named but not landed here, so every close and recycle path keeps a deaf
   arm that falls back to keeping the shell.
8. **Waves landed out of order, or only partly.** On 10-01, F-b's queue lib was on an unlanded
   branch, so 3c458424b's durable row was a no-op (`selfclose-failures-2026-10-01.md:19, :41`;
   `husk-triage-2026-10-01.md:32-39`). A fix that is present but not live reads as done.
