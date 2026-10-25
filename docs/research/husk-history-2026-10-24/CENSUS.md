# Husk-pane census: why the "neither live nor closed" pane keeps coming back (2026-06 → 2026-10-24)

Synthesis of the nine finder files in `raw/` plus `PANE-289-TIMELINE.md`. Read-only. Conventions:

- **Stores:** [c] `~/.claude/projects`, [s] `~/.claude-secondary`, [t] `~/.claude-tertiary`, [q] `~/.claude-quaternary`.
  `~/.claude-next4` had 0 hits (raw/t-secondary.md:8-9). GIT means the row has no surviving transcript; [c] keeps
  only about 30 days, oldest top-level file 2026-09-23 (raw/t-claude.md:9-12).
- **Who asked:** OP = typed by the operator (prose or `!` command). BRIEF = machine brief (fire, successor, wave or
  teammate). MACHINE = workflow result, monitor or peer mail.
- **Shas:** all 366 nine-character shas in `raw/` were checked with `git cat-file -e`. 363 exist. Missing:
  `10b2c7943`, `cc0f2d205` (both already flagged as absent by the finders) and `4e150d4a0` (unrelated). Measured.
  `†` marks a sha that is **not** an ancestor of `origin/main` (`git merge-base --is-ancestor`, measured). Where a
  trunk twin exists it is given as `→ twin`.
- Line numbers in `bin/` were read on this worktree's HEAD (`e4014fd48`†).

---

## 1. The answer

The husk recurs because a pane's end of life is not one decision but a relay among about a dozen independent
actors: session, self-close, cc-pane-runner, fullscreen guard, it2-kitty, watchdog, cc-pane-close, drainer,
cc-pane-verdict, cc-husk-sweep, boot-resume and lr-fleet. Each one reads a different subject. Session intent,
whole-cwd git dirt, custody, kitty window state and another tool's refusal string are all in play
(§3). Each one fails closed to the same designed resting state: **the shell is kept**
("AFTER THE COMMAND, THE PANE BECOMES AN ORDINARY SHELL … never an exit", `4065da386`, 08-03; `c67bda626`, 08-25).
Every act goes through kitty remote control, which is unreliable at the fleet's normal load. So a husk is
not one bug. It is what you get whenever **any** gate in the relay says no, and nothing owns the pane after that
refusal. Every investigation was scoped to one incident (each brief names its own panes; note that the
"Scope (frozen)" heading in 798afadf, edcbfa61 and 22fce1fc is a standard brief section, present in 1523 of 1908
top-level [c] transcripts, so it is not husk-specific evidence; skeptic pass, measured with `rg -l`),
and every fix adds or narrows one actor. That means 52 closer-file commits since 09-15 (8 in September, 44 in
October) and 430 matching trunk commits: 71, 101, 118, 139 by month (§4a). As a share of all trunk commits
(1520, 2360, 2537, 1818) that is 4.7%, 4.3%, 4.7%, 7.6%: flat July–September, up only in October (skeptic pass,
`git log origin/main --format=%ad | uniq -c`, measured). The next incident is then a
new combination of predicates that are each locally right: "each actor's predicate is true and the union strands
the session" (lr-stranded-husk ROOT-CAUSE.md:43-46). Lessons do not carry between actors because no shared
predicate exists. Dirt scoping was narrowed in `9c0d42af0` (07-20, untracked files ignored; it is not an
own-footprint fix) and in `78f89d73` (08-03) and `5cd17f5da` (08-04) (own footprint), and neither lesson was
carried into `570c20375` (09-04) or `d150099dd` (10-01). "Done" is also declared from a field proof on the
incident's own panes, never from a standing population metric (§4).

Pane 289 is the class in one sample:

1. The session said "Good to close: yes" and passed `--allow-dirty`. Its own paths were clean.
2. The window-scoped fullscreen guard correctly refused it (rc70).
3. The whole-cwd gate 4 wrongly refused it 9 times on 138 sibling files. Gate 4 decided the banner and the retry
   churn, not whether the pane closed: the guard sits after it (`bin/cc-pane-close:520`) and would have refused the
   same sole, fullscreen, offscreen pane on stock kitty, as it did for 280 and 282 that evening
   (`kitty-pane-actions.jsonl`, caller cc-pane-close, refused-fs; skeptic pass, measured).
4. The closer timed out 12 times.
5. The painter turned the gate-4 refusal text into "⛔ resume … stopped mid-task".
6. The sweep said COLLECTED (confirmed: `cc-husk-sweep` tool_result in 0e2799a9 at 2026-10-25T01:45:07Z,
   "289 7555024a claude4 clean-exit yes dirty COLLECTED").
7. The drainer finally dropped the row as "operator owns it … never closed" (§4d). That test is a tty **atime**
   increase (`scripts/pane-close-retry.sh:271-279`), so any read on the tty fires it; it is not proof that the
   operator typed.

**Skeptic caveat on the thesis.** The relay reading fits the July–October history, where the dominant failure
rotated. Since 10-16 one simpler cause dominates the measured incidents: the fullscreen guard on **stock** kitty
refusing a sole pane in a fullscreen OS window. It accounts for 10 of 14 failed self-close pane-days and 22 of 28
runner-kept panes (§4b, §4e). Every one of the 977 guard rows from 10-16 to 10-25 carries `fsfix:false`, so the
patched-kitty exit condition of decision e3920969aba9 never held on any day (`kitty-pane-actions.jsonl`, measured).
That class is the priced cost of a deliberate ruling whose sunset never came. It is not an emergent combination of
predicates. See "Skeptic pass".

---

## 2. Chronological census

| date (UTC) | who asked | what was asked | root cause named then | change (shas) | recurred? (evidence) |
|---|---|---|---|---|---|
| 06-05 → 06-09 | GIT | Teammate panes close too early. An iTerm2 modal appears on each reap. | `kill -TERM $PPID` hit a recycled pid. A forced close was not forced. | `41e3922f8` (close by pane id; **keeps "defer-on-dirty"**, the origin of dirt-gated close), `bc5b6d313` | Yes. Dirt deferral returns on 07-20, 08-04 and 10-01 (raw/git-early.md:18) |
| 07-02 → 07-03 | GIT | Self-close and recycle are born. | (feature) | `d090b9b56`: self-close refuses a **whole-tree** `git status --porcelain` unless `--allow-dirty`. `c90c4cace`: recycle = `/exit` plus a relaunch typed into the **surviving shell**, so the pane must outlive its session. | Shape is structural. Every later "shell kept" default descends from it (raw/git-early.md:20-22) |
| 07-13 → 07-20 | GIT | Stranded panes. 13+ finished workers pile up because "nothing could self-close". | The pgid kill took the watcher. One untracked scratch file made every co-cwd session dirty. | `dd40eca3f`, `9918ff5d7` (`--dirty-owner successor`), `6b3946371` (reaper), **`9c0d42af0`** (untracked ignored, fixed at 3 sites and not in a shared helper) | Yes: 08-04 (sibling dirt), 09-04 (sweep), 10-01 (gate 4 counts untracked again), raw/git-late.md:46-52 |
| 07-25 | GIT; backlog 4dd560d16754 (07-31) | First named "husk pane": `/exit` landed, `it2 session close` failed. | Claimed to be an iTerm2 API blip. | `4cd42ec45`: 4 retries 2 s apart, then a desk page. | Misdiagnosis. `5515ac089` (08-08): "the symptom outlived its fix", the real cause was wrong-pane identity |
| 07-24 → 08-11 | GIT | Transport and identity break after the iTerm2 → kitty move: "4 of 4 recycles … failed". | Ancestry lost under launchd. kitty reuses ids. `$ITERM_SESSION_ID` only. | `acbaba85d`, `255b3f665`, `7c0492311` ("two sibling auditors over one state with two state models"), `fe7b675ad` (composer guard, exit 67), `5515ac089` | Yes: `b95775867` (rc=67 on every agent pane, 71 refusals); `41d08635a` (09-07, launchd reaper) |
| 08-03 | GIT; `docs/plans/TEAMMATE_SELFCLOSE_INVESTIGATION.md:88-110` | Finished teammates never self-close. | A per-worktree gate is "the wrong axis when ownership is per-FILE" (:109). | **`78f89d73`** `session_dirty_mine` | Yes. Never applied to cc-pane-close, cc-pane-verdict, cc-husk-sweep or the watchdog (`rg session_dirty_mine`, raw/docs-b.md:12) |
| 08-03 | GIT | Teammate spawn typed into a shared prompt. | CC typed its spawns. | **`4065da386`** cc-pane-runner: argv, and "after the command the pane becomes an ordinary shell". | Structural: every runner pane husks by default until `74baff1ee` (10-01) |
| 08-04 | doc `kitty-selfclose-chain-2026-08-04.md` | 257 firings, 87 pairs, 0 panes closed. | A per-member verdict was computed, then `reap-guard.sh:118` re-read the **whole tree** "ONE GATE LATER" (:70-80). The runner `_fallback` keeps a shell (:51-56). | **`5cd17f5da`** (own-footprint dirt, teammate path only) | **Yes, the same defect.** `d150099dd` gate 4 (10-01) reasks the whole-cwd question, and pane 289 hit it on 10-24 (raw/docs-a.md:20) |
| 08-10 | GIT; backlog c5d25ebe630b, 42f9772d4b67 | A transplant leaves a husk beside the session. | The source pane is never closed, and the husk "could never run its own close". | `65c612e05`, `0a94736ca` | Yes: 09-08 (`68cc0a772`), 09-19/20 (panes 110/126/150) |
| 08-25 → 09-03 | GIT; doc `recycle-pane-survivability-2026-08-26.md` | Pane 32 destroyed by recycle's `/exit`. | The pane's argv was the launcher, with no shell under it. | **`c67bda626`**: reso-resume-one execs a shell "however that session ends". Invariant: "must end its command with an interactive shell" (:142). About 15 commits on one retype site (`03989de66`†…`d4527f92b`†). | It widened the husk shape to every resumed pane. Reversed for clean exits only by `6347b1731` (10-01) |
| 09-04 | GIT; doc `husk-panes-pkill-selection-2026-09-04.md` | 5 panes at a bare shell. | A sibling's `pkill -f` matched briefs held in argv. | `736632a95` (selection-keyed kill gate). **`570c20375` cc-husk-sweep born**: RESUME when "cwd holds uncommitted/unlanded work", UNKNOWN is resumed. Policy: "husk panes … are not closed by anything" (:101-103). | pkill: 08-09, 08-25, 09-04, 10-21 (husk-mass-sigterm:82-89). The dirty⇒RESUME polarity is the one pane 289 got painted with |
| 09-08 → 09-09 | BRIEF 907ac1bb [t]; doc `desk-husk-2026-09-08.md` | A sanctioned teardown was painted CRASH. The desk died at a prompt that looked like a clean `/exit`. | The attributor keys on exit 137. A kill prints the ordinary resume line. | `c53ce8bb7`† → twin `00944ee0c` (RETIREMENT); `810ee9be3` (paint the verdict into the pane); `43bc12679` (rule). Left open: "RESUME on a dirty cwd even when the dirt predates the session" (:117-119). | Yes: 10-10 (23 of 28 teardowns painted CRASH), 10-24 ("⛔ resume 7555024a") |
| 09-09 | BRIEF 6cda2e02 → 2c24bdb5 [q] | Panes 615/618 left as husks beside a new pane. Continue in place. | /limit-recover resumed into a new pane. | `109cfe4cf` (`--in-place`, every recovered pane runner-rooted) and `2d9d15d2d` ("recover in place"), with `68cc0a772`; `827f2794e` (land-gate cleanup) and `37fdc3c1a` (a rules line) are only the landed tips (skeptic pass, `git show --stat`). "Proven on a live pane … 695" (07:35:11Z). | Yes: 10-10 (pane 168), 10-20 (3e929a81) |
| 09-19 → 09-21 | BRIEF 11569d45 [s], 59681f3c/b814f44e [t]; **OP `!`** c26162f3 01:03:27Z and b814f44e 23:43:20Z [t]; MACHINE d90959db [t] | Transplant husks 110/126/150. "Make the confused middle state never recur." | A fire-and-forget relaunch. The husk predicate fires during every in-place recovery. `retire-husk-*.json` "has ZERO readers" (d90959db). | `bb5b2e4ae` (`--retire-husks`; `d13f491df`† twin), `c5b1346d6` (TRANSPLANTED). The operator ran `--retire-husks` by hand. | Yes: pane 500 two days later |
| 09-22 06:23Z | **OP 7c8201f8** [s] (also listed in [t]) | "Why cant you close remotely from here? … How can we make this more deterministic". | Admission keys on usage-limit only. No tombstone means no admissible self-close class. "A ratchet cures one verb of a two-verb class" (06:25:22). | `a91f10e8b` (its first sha `cc0f2d205` is absent); `aa51d775d` (a `--context-dead` **design** only) | Yes. Pane 500 "remains a live husk" (07:29:45). Operator re-asked 10-01 |
| 09-22 23:39Z | BRIEF 06f6a7f4 [s] | "capacity-admit refused the relaunch AFTER /exit ⇒ 3 panes stranded". | Act then check. | `d1bd54c65` (cc-lr upgrade: "probes capacity and mints a one-shot admission token BEFORE anything is typed"; its subject text is in the 06f6a7f4 transcript). `17d522824`, `3f45bfccf` and `7fa3acb4c` are test-only (skeptic pass, `git show --stat`). Later `070a6160c` (10-04, "nothing able to refuse after /exit") | Yes: 10-04 ba2e6001 [t] (token-stale, exit 9), 10-08 40dcddb3 [q], 10-18 overnight (RC2). On 10-24 pane 289 is the same shape: the close was refused after the exit |
| 09-26 → 09-28 | BRIEF 798afadf [c]; BRIEF 21fc48d5 [t] quoting OP ("we dont have hidden closed out sessions") | An in-place LR reported success over a shell. Recycle-dead pane 405. | No proof of RECOVERED. "Pane gone" and "echo unread" return the same failure. | `2e21f81aa`; CLOSE_RESUME_CUSTODY: `84218119b` (cc-resume-debt ledger) and `360bbbc54` (recycle opens and settles a resume debt). `c5626280f` is the land tip the plan names (CLOSE_RESUME_CUSTODY.md:146); by itself it is a 5-line `hooks/operator-readout.sh` change (skeptic pass, `git show --stat`) | Yes: 10-01 (`bb3345f20` recycle-dead), 10-10, 10-18 |
| 09-28 22:01Z | **OP e284b030** [s] (added by skeptic pass) | "Should we or should we not have a double Ctrl-C close out the split pane as well?" | Agent (22:01:26Z): "**My recommendation is no, about 80% confident.** A double Ctrl-C should leave the pane open at the shell, as it does now." | none. The shell-kept default was reaffirmed 3 days before `74baff1ee` | The operator's own question about close-on-exit, answered "keep the shell" |
| 09-29 → 09-30 | BRIEF FLEET_V2 W5a: 3c57e64e [c], 84f3533b/967a1469/d3649568 [s]; **OP 6d973d05** [s] 19:18:55Z "are these accidentally not closed out?" (added by skeptic pass; the 9 rig test tabs were closed by their session, 19:24:03Z) | A rig re-drives husks. | Records go unread between components. | `18910dd50` (`--husk`, `--relaunch-at-shell`), `f7723369a`, `6aaeaa44c` | Yes: `HUSK-RETIRED/no-stub` still present 10-20 (1af834a8) |
| **10-01 03:14Z** | **OP d97e7a14** [c] | The contract: "if a session is to recycle/handoff, it should resume into Claude Code, if a session is to close, it should close out that pane entirely". 7 of 39 windows were husks. | Stuck kitty socket. devserver-gc killed a lead (brief in argv). "Nothing ever closes a pane after Claude exits." The watchdog mislabeled. The sweep named the wrong sid. "Auto mode refused to let me close them" (04:06:34Z). | `55a2a049e` (doc); `13608cd78` (devserver-gc; `5a673c141`† twin) | **Yes, within 1.5 h**: 55/69/76 at 05:44:49Z. The operator ran the close script himself at 05:30:03Z |
| 10-01 04:05 → 18:52Z | BRIEF d86e6bd4 [t] + **OP** 15:46:36Z and `!` 17:46:08Z; BRIEF 09c26b2b [c] + **OP** 16:26:14Z and `!cc-pane-close` 16:55:31Z | Implement F-a..F-e. "If a pane looks like it meant to close itself but didnt … we should be able to close the pane". | kitty 610 socket stuck (128 queued, 59 zombies; pane-lifecycle plan :38). Each close was one attempt. Agent closes blocked by the auto-mode classifier. | `74baff1ee` (a clean exit closes the pane), `7eb551b39`, `b6bf10c0c`, `bbc40d207`, `476712b2f`, `3156c4dcd`, `bd39fb7c7`, `b6727f1d9`, **`d150099dd` cc-pane-close with gate 4 "no uncommitted work in the session's cwd"**. Its body says pane 76 was refused on the first live dry run. Decision 337e100f5c71 keeps hand-opened windows open. | **Yes.** Gate 4 is unchanged in predicate (`git log -G porcelain`: only d150099dd and `54acfdb98`, raw/git-late.md:31-35) and refused pane 289 |
| 10-01 18:45 → 20:50Z | BRIEF c197cdd9 [t] (backlog 21ba8983cd4a); BRIEF edcbfa61 [c] | Seven lifecycle fixes. Boot-resume revived a self-closed session. | The verdict ignored custody. Boot-resume did not read the self-close marker. "My completion note sits in a mailbox nothing reads." | `904fdd205` (COLLECTED), `e44823f02`, `4fad69e1d`, `eee5cf8c5`, `6347b1731`, `c3d5a71dc` (watchdog hands to the closer after 20 s), `ba04df7b3` | Yes. On 10-24 the sweep said COLLECTED while the new painter (`99acf1d9f`) said RESUME |
| 10-09 → 10-11 | rail BRIEF 04bfa0e6 [c]; aa3e64c4, f28815ed [q]; 4f7d7e9e [t] | Relaunch writes failed, "pane stranded at a bare shell". Pane 44/134. | F1: transport at about 45 load/core. F2-F4: regression `f14b42653` (the slash menu read as a dialog). An alarm to a nonexistent role. Six parser copies. `lrp_husk_owner_row` "has filed 0 rows ever". | `82f3c0dc2`†, `0e882c9ac`, `0584f0720`, `b588b5a2d`, `1ec83ec17`, `ccf5ed35f` | Partly. "4 of the 9 exits since it landed" still typed (RECYCLE_KITTY_FIXES) |
| **10-10 04:44Z** | **OP 92928fee** [c]; BRIEF 197b48ee [q] | "are we good to close this pane; has this pane been resumed elsewhere?" The agent first said yes, then reversed itself (04:45:25Z). | 5 causes (ROOT-CAUSE.md:36-64): keep-work answered, no owner of "moved but never started", four refusing entry points, no draft carry, and doctrine handing the draft to a human (Ctrl-U, 04:56Z). | `2158f14ad`, `22df298c6`, `30ecec45d`, `0584f0720`, `b68fa8a25` (field proof: "pane 168 recovered live") | Yes: 10-14 keep-work recurred in the self-recycle lane (pane 434); 10-18; 10-20 |
| 10-10 18:17Z | BRIEF bb804b70 [q] | A lead-ordered teardown was painted "⛔ NOT A CLEAN EXIT … KILLED" (23 of 28 fleet-wide). | The watchdog needed one signal; absent it, it painted CRASH. | `307655279` (teammates only) | Yes, the same class: pane 289 "⛔ resume" after "Good to close: yes" |
| 10-14 | doc `recycle-failure-2026-10-14.md` | Pane 434 "succeeded" without painting. | Keep-work answer again; non-interactive CC on a piped stdout. | `c148eeca5` (F6: a refused window **falls through to a shell** on purpose) | Adds a kept-shell path by design |
| 10-15 → 10-17 | BRIEF b9ae7b04 [q], f7351f3b [s]; BRIEF 087c2a52 [q] ("C needs nothing; the husks are gone"); decision e3920969aba9 | kitty SIGSEGV on removing the last pane of a native-fullscreen window. | AppKit fullscreen teardown (`kitty-crash-2026-10-15/README.md`). | `fd0d17f57`, `62372906a`, `265790f36`, `ebaece47d`, `b8d8bfca9` (relax only on a patched build **and** onscreen), `1211646fb` (it2-kitty exit 70, page husk-fs, "No work at risk"); revert `9d7f3c216`† of `d4b7c9ff2` (the reverted commit is on trunk; the revert is not) | **Yes, a new husk class by design.** rc70 is first seen 10-16T22:20:35Z (pane 210); 10 rc70 pane-days through 289 (§4b). The class itself is older than the exit code: sole-pane fullscreen refusals of panes 55, 80 and 181 were logged from 10-16T08:23Z, before `1211646fb` existed (`kitty-pane-actions.jsonl`, skeptic pass, measured). Every guard row from 10-16 to 10-25 has `fsfix:false`, so the `b8d8bfca9` relax never applied |
| 10-16 | doc `teammate-resurrection-2026-10-16/REPORT.md` (`8fd2a38dd`; added by skeptic pass) | Teammate web-next16 did not close. It was later relaunched as an orphan in a new window. | The TeammateIdle reaper timed out at 5 s on a worktree "SHARED by 7 members". The upgrade drainer read the lead's graceful close as a failed relaunch, and `cc-resume-debt settle` reopened a paid debt and relaunched it (REPORT.md:13-22) | research | Another instance of actors undoing each other, after edcbfa61 (boot-resume). This time the undoing actor was the 09-28 custody fix |
| 10-18 → 10-19 | BRIEF 5a6b8a40 [t] quoting OP ask (c): "no pane may sit as a plain shell after leaving Claude"; 94747d64 [t]; 9057bfff, 150304ab, 5056b7f3 [c] | 17 overnight husks. cc-pane-close refused all 18. | RC2: admission after /exit. RC4: untruthful verdicts, and a closer that cannot close. | `7a33cb733`, `54acfdb98` (gate 4 skipwork for never-launched or moved-live only; `fs_guard_pane` wired), `a0a41b5d1`, `f3944c0f0`, **`fd34d855d`** (placement: every OS window fullscreen; overflow fires open `--os-window-state=fullscreen`) | Yes: 10-22, 10-24. fd34d855d (with `6fd8c7068`, 10-18, `cc_place_pane` "else a fullscreen OS window") sends overflow fires into sole-pane fullscreen windows that the guard must refuse (raw/git-late.md:73-82). It did not start the class. Guard refusals hit 5 distinct windows on 10-16, before either commit (`refused-fs` on panes:1 for 3, 55, 80, 181 and 210). Afterwards they hit 2–8 distinct windows a day, counting every `refused-*` verdict from every caller (skeptic pass, `kitty-pane-actions.jsonl`, measured). Window ids are reused, so these counts are approximate |
| 10-20 | BRIEF e4056b1b [q] | Stranded husk 3e929a81 "after 3 husk recoveries". | A stale premise: the successor was already live. | none | The store lagged the live state |
| 10-21 15:44Z | **OP 2c5e09dc** [s] | "a lot of partially closed sessions (ie. Claude Code closed, but pane itself still open)". | `pkill -f "next start" -P` turned `-P` into a pattern and hit 9 sessions and 6 teammates. "The open panes are intended … 'page, never auto-recover'" (17:00:51). | `f6d2418b4`, `d7d5df709` (sweep allowlisted); `948810da6` (gate 3 accepts the self-close stamp; via MACHINE 5d19ef73 [t]); `2f41fbde1`, `160bd4cb3`. The operator ran `cc-husk-sweep --resume --yes` himself (17:02:42). Structural options (brief by file, rename the ping, an exec shim) were not built (husk-mass-sigterm:96-100). | Yes, the next day |
| 10-22 15:55Z | **OP e881b713** [c] | "How come all of these panes are left halfway open". 9 panes. | `timeout 15` around `kitty @ launch` killed only the client. The late pane had no owner, and the runner fell back to a shell after 300 s. | `da0f61ce6` | Same day: panes 85/42/101 |
| **10-22 23:21 → 10-23 08:05Z** | **OP d03e3361** [s]; BRIEF d7e2a7a8 (Wave A) [c], 35617ab9 (Wave B) [s] | "Don't just investigate the individual cases but the root reason … long-term fix." | "**A pane's end state has no owner**" (REPORT.md:18-22). RC1: misdirected self-close (inherited `KITTY_WINDOW_ID`). RC2: one-shot closes. RC4: four screen writers. RC5: a peer's death is unseen. Gate 4 is named as an abandonment path (investigators.md:251). | `aea01028e`, `8d69845a0`, `5d0be0366` (husk queue), **`99acf1d9f` cc-pane-verdict** (`"uncommitted change"` → RESUME), `d82aa7860` (hf_husk_row hands to the closer, with no waiver), `2c94cf6d8`, `c820e86f1`, `85b1d7131`. The operator ran the close script (01:16:31). Claimed at 08:05:24: "root causes are fixed and live". | **Yes, the same afternoon** |
| 10-23 16:11 → 23:02Z | **OP d03e3361** round 2 [s] ("Good to close?"); BRIEF 22fce1fc (Wave C) [c]; BRIEF dfb193b5 [t] (re-land: "9 of 9 path(s) … origin/main LACKS") | Panes 165 and 144-147 refused 8-44 times under "closes when it does". | The it2 shim routed to iTerm2 from launchd. "Every automatic close since the waves landed has therefore failed. Yesterday's tests stubbed that check" (17:24:23). The drainer was starved. RC3: a sole fullscreen pane "can never be closed automatically". | `957279537` (**gate 4 pinned by a test** to protect crashed teammates), `975dd4d94`, `03696fdd5` (row 2 only; STATE map untouched), `7f7b9c293`, `3f1a77b71`, `4cb749ceb` (hold=operator), `0375891ac` (`fa6638ba2`† twin). The operator pressed ⌘W on 165. | Yes. "kitty has no lingering dead panes" at 10-24T05:40:58, then pane 289 the same day |
| **10-24 23:52Z** | session 7555024a [q] (BRIEF: Track C fired by lead 5cc74e8c); siblings 5674517a [q] (23:29Z), dccaf095 [q] (10-25T01:54Z) in the same cwd | "✅ Good to close: yes" (23:52:11.944Z). `self-close --terminal`, refused on dirt, own paths judged clean, then `--allow-dirty` (23:52:38.377Z). **The transcript ends with no tool_result.** | rc70 (correct: sole pane, FS, offscreen, os_window 25). Gate 4: 138 sibling changes. Painter: DONE → CANTTELL → RESUME (PANE-289-TIMELINE.md:7-14). | none on trunk | Siblings show the same "refusing self-close: dirty git tree" in the same cwd; f583a3fd had 112 changes on 10-21 |
| 10-25 01:42Z (10-24 CDT) | **OP 0e2799a9** [c]; BRIEF 06457213 [c] | "closed sessions should … close out the entire Kitty Terminal pane … introspect all of the previous sessions". | (this census) | `3ebeaf508`† (husk-pane skill), `ab9e2468f`† (maps), `e4014fd48`† (timeline). `bin/cc-pane-close` has no 10-24 commit. | open |

The operator raised the problem in at least 12 sessions over 33 days. Count method: operator-typed prose rows in
raw/t-*.md, plus quoted asks, plus two found by the skeptic pass. Dates: 09-22 (7c8201f8), 09-28 (21fc48d5, quoted;
e284b030), 09-29 (6d973d05), 10-01 (d97e7a14 and d86e6bd4), 10-10 (92928fee), 10-18 (5a6b8a40 ask c, quoted),
10-21 (2c5e09dc), 10-22 (e881b713 and d03e3361) and 10-25 (0e2799a9). Only 4 of these state the explicit two-sided
contract ("resume into Claude Code … or close out that pane entirely"): d97e7a14, 5a6b8a40 (c), d03e3361 and
0e2799a9. The others are questions (7c8201f8, 92928fee, e284b030) or one-sided complaints. Where the contract is
stated, the wording barely changes (raw/t-claude.md:45-46). The operator ran closes or resumes by hand at
least 8 times: 09-20 ×2, 10-01 ×3, 10-21, and 10-23 ×2 (a script and ⌘W on pane 165). On 10-24 the drainer gave pane 289 up to the
operator because its tty's atime rose. That shows a read on the tty, not necessarily operator typing (§1, item 7).
Estimated by counting the OP `!` rows and quotes above. One of the 09-20 runs (c26162f3, `cc-do 45cc39bf65c3`)
ran a self-close that ABORTED on all three panes (raw/t-tertiary.md:40), so it was a hand attempt, not a hand close.

---

## 3. Mechanism inventory (what exists today) and the state-model split

| layer | born | meant to fix | subject its predicate reads | default on refusal or unknown | pane 289 output |
|---|---|---|---|---|---|
| Session close line "Good to close: yes/no" | close rules; `01ba2fcf6` (10-18) re-meant it as "nothing drivable open" | intent to end | the session's own judgment, transcript text only | — | **yes** (23:52:11Z) |
| `handoff-fire.sh self-close` | `d090b9b56` (07-02). Gates added after: `9918ff5d7`, `4cd42ec45`, `9abb0c0e9`, `5515ac089`, `889c65600` (exit 8), `aea01028e`, `1211646fb` (rc70), `2f41fbde1` (intent record), `d82aa7860` (hand-off) | ending a fired peer's pane | its own pane identity; **tracked** dirt only (`--untracked-files=no`, handoff-fire.sh:15496-15501) with the `--allow-dirty`/`--dirty-owner` waiver; the guard | page + husk row → cc-pane-close | passed its own dirt gate with the waiver → `STILL-PRESENT-rc70` |
| cc-pane-runner close-on-exit | `4065da386` (08-03, keeps the shell); `74baff1ee` (10-01, a clean exit closes); `7a33cb733`; `265790f36` (guard veto); `c820e86f1` | ending a pane when claude exits | exit rc (closes only on 0 or 75, husk-mass-sigterm:71-73); guard | **keep the shell** | "claude4 exited 0 — guard: refused (refused-fs)", kept |
| reso-resume-one | `c67bda626` (shell after every end); `6347b1731` (a clean exit closes); `c148eeca5` (a refused window stays readable) | recycle survivability | exit rc; guard | keep the shell | n/a |
| it2-kitty actuator | composer guard `fe7b675ad` (exit 67); `62372906a` (guard); `1211646fb` (exit 70); `da0f61ce6` (adopts a late pane) | safe close and launch | composer text; window state; reachability of the kitty socket | refuse | rc70 |
| kitty-fullscreen-guard | `fd0d17f57` (10-15); `b8d8bfca9` (relax only on patched **and** onscreen) | the kitty crash | OS-window state (sole pane, FS, onscreen) | refuse (rc 3) | `refused-fs`, panes:1, onscreen:false (timeline :7,:10). `fsfix:false` on all 977 guard rows 10-16..10-25 (`kitty-pane-actions.jsonl`, skeptic pass, measured): the patched build never ran |
| Placement policy | `6fd8c7068` (10-18, `cc_place_pane`: "split with room, else a fullscreen OS window, never a tab"), `122d5ff18`, `242c34d5a`; `fd34d855d` (10-19, overflow fires go into fullscreen OS windows) | operator layout rule | — | — | made 289 a sole pane in OS window 25 |
| lead-crash-watchdog | `810ee9be3` (09-08 paint); `b6bf10c0c`; `e44823f02` (COLLECTED); `c3d5a71dc` (→ closer); `307655279`; `2c94cf6d8`; `7f7b9c293` | truthful death verdict | exit reason **plus whole-cwd dirt** ("uncommitted work in personal") | CRASH or CANTTELL | "ended cleanly" **and** "uncommitted work" → CANTTELL at 23:55 |
| `bin/cc-pane-close` | `d150099dd` (10-01); `b6727f1d9`, `62372906a`, `ebaece47d`, `54acfdb98`, `948810da6`, `ab7e82e9f`, `957279537`, plus `eef500138` (10-22, a kalloc `cc-run` wrapper sweep over ~90 sites, no close behaviour) (9 trunk commits, measured `git log origin/main -- bin/cc-pane-close`) | closing a husk while kitty RC is down | gate 3: **session** intent, stamp, custody (:489-506). Gate 4: **whole-cwd** `status --porcelain \| grep -c .` (:508-511), no waiver (`rg allow.dirty`: 0 hits). Guard asked **after** gate 4 (:520) | refuse | gate 3 passed ("Good to close: yes"); gate 4 refused 9× (138); 12× rc124 timeout |
| pane-close-retry drainer and queue | `3156c4dcd`, `bd39fb7c7`, `5d0be0366` (husk row, 10-22), `85b1d7131`, `3f1a77b71`, `4cb749ceb`, `0375891ac` | one-shot closes | row kind; the closer's rc | retry each tick; hold=operator; drop | 21 attempts, then "its tty was typed in since — the operator owns it; row removed, never closed" (01:45:55Z) |
| `bin/cc-pane-verdict` | `99acf1d9f` (10-22, "one writer"); `03696fdd5` | four painters disagreed | **substrings of the closer's last line** (:83-90): `"fullscreen guard"`→DONE (:85), `"uncommitted change"`→RESUME (:86), else CANTTELL (:90). It has three callers (runner, watchdog, reconciler), and the last one wins. | CANTTELL | DONE (23:53:36) → CANTTELL (23:55:00) → **RESUME "138 unsaved files"** (00:00:14) |
| `bin/cc-husk-sweep` | `570c20375` (09-04); `c5b1346d6` (TRANSPLANTED), `bbc40d207`, `904fdd205` (COLLECTED), `54acfdb98`, `975dd4d94`, `d7d5df709` | resuming killed sessions | close text, **whole-cwd** `work_of()` (:508-516), custody (:560-563) | RESUME, and UNKNOWN is resumed (:42-45) | COLLECTED, per the brief. Read-only verdicts are not logged (husk-sweep.jsonl holds only 8 `resumed` rows) |
| crash attributor / cc-close-attrib | `fc18a0172`† → twin `1937ed751` (07-24); `c53ce8bb7`† → `00944ee0c` | death attribution | exit code or signal | CRASH | `STILL-PRESENT-rc70` row |
| boot-resume | `ba04df7b3` (10-01), `160bd4cb3` | restore after reboot | self-close marker | resume | — |
| lr-fleet `--retire-husks` / cc-limited `--reap` | `bb5b2e4ae` (09-20) / (names only, 7f533f05) | LR husks | tombstone or lock | name, do not close | — |
| reap-guard / teammate-auto-shutdown | `5cd17f5da`, `78f89d73` | teammate closes | **own-footprint** dirt (`session_dirty_mine`) | defer | — (the one place the lesson lives) |
| husk-pane skill | `3ebeaf508`† (10-24) | manual diagnosis | — | — | — |

**How they disagree (the split):**

- **Different subjects.** Gate 3 is keyed on the session and gate 4 on the repo (memory
  `gate-composition-two-halves-one-subject.md`; raw/logs-backlog.md:253-255). Self-close counts tracked files and
  honours a waiver. The closer counts every porcelain line and honours none. The sweep and the watchdog count the
  whole cwd. reap-guard counts own paths only. That is four dirt predicates for one fact (raw/git-late.md:103-115).
- **Gate order picks the banner.** In cc-pane-close, gate 4 (:511) runs before the guard (:520). Gate 4 refused
  first, so the painter saw "uncommitted change" and painted RESUME. A guard-first order would have produced
  "fullscreen guard", which maps to DONE ("⌘W closes it · last pane of a fullscreen window", cc-pane-verdict:85 and
  :98). That was the first paint, and it was correct (PANE-289-TIMELINE.md:8, :28-30).
- **The contract is not implemented.** synthesis.md:278 puts "Good to close: yes" under DONE. cc-pane-verdict:69-93
  derives state only from the closer's line plus the pane-exit record. It never reads the sweep row, custody, the
  stamp or the waiver (raw/docs-b.md:31). Every gate-4 refusal comes from a session that passed gate 3, so every one
  is painted "stopped mid-task" falsely (raw/git-late.md:92-96).
- **Inputs are dropped at hand-offs.** `hf_husk_row` (`d82aa7860`) carries reason, tty, producer and the socket.
  It carries no "Good to close", no waiver and no owned-path proof. The 08-04 doc had already convicted this pattern
  ("verdict thrown away before the gate that actually blocks", kitty-selfclose-chain:70).

---

## 4. Recurrence measurements

### 4a. Fix volume (measured)

| measure | value | source |
|---|---|---|
| trunk commits matching husk/pane-close/self-close/… grep | 430: 07: 71, 08: 101, 09: 118, 10: 139 | raw/t-claude.md:86-87 (`git log origin/main -i -E --grep`) |
| `--all` matches 06-01..09-15, dedup by subject | 2753 → 1009 | raw/git-early.md:8 |
| non-checkpoint subjects on 7 closer files since 09-15 | 52 (Sep 8, Oct 44) | raw/git-late.md:10-12 |
| trunk commits on `bin/cc-pane-close` / `bin/cc-pane-verdict` | 9 / 2 (10-01..10-23) | `git log origin/main --oneline -- <file>` (this synthesis) |
| reverts of a close/husk mechanism on trunk | 0. `9d7f3c216`† reverts `d4b7c9ff2` (on trunk) on a branch only | `merge-base --is-ancestor` (this synthesis); raw/git-early.md:12 |
| backlog husk ids | 32 ids, 58 events, **all done** | raw/logs-backlog.md:176-178 |

### 4b. In-session self-close failures (`close-attrib.jsonl`, failed (pane, day) incidents per week; measured, raw/logs-backlog.md:48-58)

| week | 08-03 | 08-10 | 08-31 | 09-07 | 09-21 | 09-28 | 10-05 | 10-12 | 10-19 |
|---|---|---|---|---|---|---|---|---|---|
| incidents | 5 | 3 | 2 | 1 | 1 | 1 | 5 | 5 | **13** (rc70 ×9) |

The dominant failure code changed over time: rc124/rc3 in August, rc67 in August–September, rc1 and no-registration in the week of 10-12, and
rc70 from 10-16. Since 10-16T22: 61 closed, 10 rc70, 2 unverified-rc124, 1 rc1 and 1 rc67, so about 14 of 75
pane-days failed and 71% of those were rc70. `rg -c STILL-PRESENT-rc70 close-attrib.jsonl` = 10 (this synthesis,
measured). The weekly `closed` volume fell from 90–226 to 2–23 after 10-05. The estimated cause is that `74baff1ee`
moved closes into the runner, which does not log to close-attrib, so the denominator moved (raw/logs-backlog.md:67-71).
Skeptic pass, measured (`jq` over close-attrib by day): the drop is in self-close close *attempts* of every
verdict, not only in `closed` rows. There were 9–33 a day from 09-26 to 10-01 (24 on 10-01) and 1–13 a day from
10-02 on. close-attrib writes a row only when a close is attempted, so a pre-close gate that began refusing on 10-01
would produce the same drop (`eee5cf8c5` and `4fad69e1d` landed that day). The cause remains an estimate.

### 4c. Post-exit closer refusals since 10-15 (`pane-close.jsonl`; measured, raw/logs-backlog.md:84-95)

| category | rows | panes |
|---|---|---|
| launch never started / window not named | 257 | 30 |
| no registration in this kitty's lifetime | 24 | 22 |
| remote control down + fullscreen | 23 | 11 |
| fullscreen last pane | 17 | 3 (165, 280, 282) |
| nothing says it meant to end | 11 | 9 |
| **cwd holds N uncommitted change(s)** (gate 4) | **9** | **1 (289)**: the only gate-4 rows in the log, which starts 10-01T16:39Z. Gate 4 had refused once before, unlogged: pane 76 in the 10-01 live dry run (`d150099dd` body) |
| closed-kitty-unreaped | 7 | 7 |

### 4d. Pane 289 (measured by this synthesis)

| log | measure | value |
|---|---|---|
| `pane-close-retry.log` | attempts on `pane=289` | 21: **9 × rc=1 (gate 4) + 12 × rc=124 (closer exceeded 60 s)** |
| same | end | 01:45:55Z: "its tty was typed in since — the operator owns it; row removed, never closed" |
| `pane-close.jsonl` | rows with 7555024a | 9, all "…personal holds 138 uncommitted change(s)" |
| `pane-say.jsonl` | rows with 7555024a | 5: DONE → CANTTELL → RESUME within about 7 min |

The brief's "21+ refusals" are therefore 9 refusals plus 12 timeouts. Closer rc124 timeouts total 25 rows across 6
panes since 10-23 (145, 146, 165 ×5, 280 ×4, 282 ×2, 289 ×12; raw/logs-backlog.md:121-122).

### 4e. Painter instability and kept panes (`pane-say.jsonl`, from 10-19; raw/logs-backlog.md:144-154)

- cc-pane-verdict paints: NOTHING 16, DONE 16, CANTTELL 12, RESUME 1 (pane 289). Pane 165 flipped DONE ↔
  CANTTELL 8 times across 14 paints on 10-23.
- The runner kept 28 distinct panes since 10-20. 22 of them were kept by the fullscreen guard (149, 170, 363, 476, 54, 56, 42,
  50, 63, 72, 81, 82, 80, 90, 88, 89, 106, 133, 165, 280, 282, 289) and 6 because "kitty didn't answer".
- Estimated, as a union of three sets: **about 35 husk incidents on the self-close and close-on-exit paths since
  10-15, plus about 40 abandoned or never-started panes** (raw/logs-backlog.md:156-172).

### 4f. Shared-checkout dirt and observability (measured, raw/t-quaternary.md:55; raw/logs-backlog.md:114-117)

- 44 top-level [q] transcripts contain "refusing self-close: dirty git tree", and 37 contain `--allow-dirty`. All 4
  hits from 10-20 on are `~/Development/personal` (112 changes on 10-21, 138 on 10-24/25).
- 7555024a, 5674517a and dccaf095 all end on the self-close `tool_use` with no `tool_result`, so the refusal
  exists only in the logs.
- The drainer log is 88% noise (22875 of 25949 rows are "already paged — held"). Rows were held for 11 days until
  `85b1d7131`. `husk-sweep.jsonl` logs only resumes (8 rows, 10-21). **No log counts husk panes per day.** The
  finders missed one usable source: `~/.claude/logs/kitty-pane-actions.jsonl` (1466 rows, from 10-15). It logs every
  fullscreen-guard verdict with pane, `panes`, `onscreen` and `fsfix`: 77 `refused-fs`, 8 `refused-timeout` and
  12 `refused-unknown` (skeptic pass, measured). It is a per-day count of the dominant class since 10-16, not of all
  husks.

---

## 5. Open backlog and decision rows (the filed state)

| id / doc | kind | state | bearing on the class |
|---|---|---|---|
| 32 husk backlog ids | backlog | **all done** | No open item exists while §4b rose to 13 a week (raw/logs-backlog.md:176-178, 315-319) |
| f5f9ff77284c, 4a2e950efe4f, e9b218ff00bf, 3dde5e53312f | backlog | done | Four items asked a human to close or restart because agents were refused |
| 337e100f5c71 (10-01) | decision | actioned | Hand-started windows stay open on /exit. Fleet panes close from inside (`74baff1ee`) |
| e3920969aba9 (10-16) | decision | actioned | "Keep blocking agent last-pane closes on stock kitty". Relax only when patched and onscreen. Precondition **unmet on every day**: all 977 guard rows from 10-16 to 10-25 carry `fsfix:false` (`kitty-pane-actions.jsonl`, skeptic pass, measured) |
| 891ea9e9d0f3 | decision | actioned | Stay on official kitty, no re-sign, so the `b8d8bfca9` relax never applies (kitty-lastpane-move README:96-104) |
| 0a8ffe58562a (10-01) | decision | actioned | Patched kitty swap armed (`eec8e995f`). It never took effect: the guard reports `fsfix:false` on every row 10-16..10-25 (skeptic pass, measured) |
| a41897063971 | decision | actioned | Upstream kovidgoyal/kitty#10671 and #10672. #10632 (RC deafness) is fixed only in 0.50.0, not 0.49.2 (kitty-deaf-episode REPORT:24-27) |
| operator rule, 2026-10-10 | ruling | standing | "zero human in the loop" (lr-stranded-husk ROOT-CAUSE.md:7-9). This **conflicts** with the auto-mode classifier refusing agent closes (d97e7a14 04:06Z; d03e3361 00:11:58Z) and with e3920969aba9's ⌘W path |
| fd34d855d placement (10-19) | rule | live | Fires go into fullscreen OS windows alone, which **conflicts** with e3920969aba9 and guarantees an rc70 husk for every lone fired peer (round2 synthesis.md:5 RC3). The same conflict already existed under the operator's all-fullscreen layout before this rule (sole-FS refusals on 10-16; §2 row 10-18) |
| b7ce699affec | backlog | open (plan `kitty-deadlock-recovery-2026-10-01.md` in-progress) | W3 durability build for a stuck kitty socket |
| 562b31cb7d99 | backlog | parked to 2026-10-26 | close-behavior census (the meaning of "Good to close") |
| 64cd62f75524 | backlog | ≥ 2026-11-02 | kitty-lastpane-move option E |
| 1ef91f32a58c | packet | recommended No | kitty-deaf fd hypothesis |
| `husk-panes-2026-10-22/investigators.md:251` | doc gap | open | "gate 4 refuses. No record that would trigger a retry … → abandoned" |
| `desk-husk-2026-09-08.md:117-119` | doc gap | open since 09-08 | RESUME on pre-existing dirt, now in cc-pane-verdict:86 |
| `pane-end-of-life-2026-10-22.md` | plan | "complete" | The CONTRACT (DONE includes "Good to close: yes") is not implemented. C6 has no read-back. The 09:12Z SIGTERM sender is unresolved (a7-sigterm.md) |
| `husk-mass-sigterm-2026-10-21.md:96-100` | doc gap | not built | Briefs held in argv. The structural fixes for pattern kills were not taken |
| `aa51d775d` | design | unbuilt | `--context-dead` self-close class (09-22) |
| `RECYCLE_KITTY_FIXES.md:74,84,96` | plan | "complete" | A teardown that meets the bgwork dialog leaves the pane open. Old shells have no hook. A deferred lane has no retry ticket |
| branch-only shas | git | unlanded | `3ebeaf508`†, `ab9e2468f`†, `e4014fd48`† (this branch); `c6fbe99da`†; `10b2c7943` and `cc0f2d205` are absent |

---

## 6. What a fix must do to remove the class (not add a layer)

The invariant to enforce is the operator's own: **a pane holds a live Claude Code session, or it does not exist;
a bare shell over a dead fleet session is an alarm, never a resting state.** A fix removes the class only if all of
the following hold. Each item names the evidence it answers.

1. **One end-of-life record, written by the session before it exits, and read by every actor.** The session writes
   it while it still has context: intent CLOSE or CONTINUE(successor), its **own** paths' state, and any waiver.
   Self-close, runner, watchdog, cc-pane-close, drainer, cc-pane-verdict, cc-husk-sweep and boot-resume all read this
   record. None of them re-derives intent from transcript text, cwd dirt or another tool's stdout. This removes the
   pattern of inputs dropped at hand-offs (`d82aa7860` without a waiver; 08-04 :70) and of actors undoing each
   other (edcbfa61 boot-resume; 92928fee poller).
2. **One decision function, and painters that only render.** A single shared library returns
   LIVE / CLOSE / RESUME / OPERATOR-ONLY(reason) for a pane. Every closer and painter calls it. Delete the substring
   mapping in `bin/cc-pane-verdict:83-90`. The banner must be a pure function of that decision, so the last caller
   cannot win (timeline :24-27) and one pane cannot show RESUME and COLLECTED at once.
3. **Work-at-risk keyed on the same subject as intent.** Use `session_dirty_mine` (`78f89d73`) and own-footprint
   (`5cd17f5da`) at **every** site: cc-pane-close gate 4 (:508-511), cc-husk-sweep `work_of()` (:508-516) and the
   watchdog. A shared cwd's sibling dirt must never decide another session's end. Protect a crashed teammate (the
   reason for `957279537`) on that teammate's own paths too. Add one cross-closer test that fails if any actor counts
   whole-cwd porcelain.
4. **Admit before you act: prove the close is possible before the session ends.** If the guard would refuse
   (sole, FS, offscreen pane) or kitty is deaf, the session must not exit into a husk. It must first move the pane into a
   closable state (leave fullscreen or join a windowed OS window) or stay live and report. This is the
   06f6a7f4 / `070a6160c` lesson applied to closes. The **placement rule `fd34d855d` and decision e3920969aba9
   must be reconciled by the operator.** As long as lone fired peers open into offscreen fullscreen windows on stock
   kitty, rc70 husks are guaranteed (22 of 28 kept panes since 10-20 are fullscreen-guard keeps, §4e). Reverting
   `fd34d855d` alone would not remove the class, because sole-FS refusals predate it (10-16). The operative switch is
   the kitty build: e3920969aba9's own exit condition, the patched build, has never been true (`fsfix:false`, §3).
5. **Invert the default: the close is the pane's own exit, not an RPC.** A session whose record says CLOSE ends its
   pane by its own process exiting, as `74baff1ee` does. The shell is not the fallback. Only CONTINUE keeps the
   pane, and it does so by relaunching claude in the runner rather than typing into a shell
   (`4065da386`/`c67bda626`/`c90c4cace` made the shell the default). kitty remote control becomes an optional
   fallback, so deafness under load (10-01, 10-09, 10-22) can no longer leave a husk. Limit (skeptic pass): this
   item does not cover a sole pane of a fullscreen window on stock kitty. A process exit there empties the window,
   and emptying the window is the 10-15 crash. `265790f36` vetoes the runner's own exit for exactly that case, and
   the runner's guard read itself needs kitty remote control (6 of 28 kept panes were "kitty didn't answer", §4e).
   Item 5 therefore depends on item 4.
6. **Every refusal has an owner and a terminal state.** A refusal whose inputs cannot change (sibling dirt,
   offscreen FS) must not be retried 21 times. It goes once to OPERATOR-ONLY with one honest page. A refusal whose
   inputs can change (deaf kitty, an unlanded branch) gets a retry keyed on that input changing. Count closer
   timeouts (rc124, 25 rows) as a failure class with its own owner.
7. **A standing population invariant, not per-incident proof.** Every N minutes, count panes at a bare shell whose
   last child was a fleet claude, across all causes, and write the count to one log. "Done" means 0 for 7 days on
   that log. A single field proof does not count (pane 695 on 09-09, pane 168 on 10-10, "fixed and live" on 10-23
   08:05). Re-open automatically on a non-zero day. The close-attrib denominator has already moved once without
   anyone noticing (§4b).
8. **Composed replay tests in the topology where the failures happen.** One end-to-end suite must run
   self-close → runner → guard → closer → drainer → verdict → sweep from a launchd-like parent, with no stub that
   answers `session list` regardless of env (round2 RC7). Fixtures: Good-to-close-yes in a shared dirty cwd as a
   sole FS pane (pane 289); a deaf kitty; never-launched; a crash mid-task with own dirt; a teammate crash.
9. **Agents may execute the decision.** The auto-mode classifier and allowlist must permit the close or resume that
   the decision function emits. Otherwise every OPERATOR-ONLY and many CLOSE outcomes route to the operator, against the
   10-10 zero-human ruling (four backlog items and at least eight hand runs, §2).
10. **Brief the invariant, not the incident.** Future briefs must not freeze scope to one incident's panes
    (798afadf, edcbfa61, 22fce1fc). The deliverable is items 1–3 plus the item-7 metric reaching zero. A new
    incident is a regression against that metric, not a new lane.

---

## Finder disagreements, resolved

- **"21+ refusals".** These were 21 drainer attempts: 9 gate-4 refusals and 12 rc124 timeouts. docs-a found only 9
  rows because it read `pane-close.jsonl` (§4d, measured).
- **Location of 7555024a.** It is absent from [c] and [s]/[t] and present in [q]
  (`-Users-chrisren-Development-personal/7555024a-….jsonl`, raw/t-quaternary.md:23). d86e6bd4 is in [t].
- **Fullscreen-guard birth.** git-early's "earliest 10-19 (`60c87719f`)" is wrong. `fd0d17f57`, `62372906a` and
  `265790f36` are dated 2026-10-15 (`git log -1`, measured).
- **"Trunk 09-08" for `c53ce8bb7`.** That sha is off trunk. The trunk twin is `00944ee0c`. Likewise `d150099dd` is the trunk copy of
  gate 4 (`ddeeb6b42`† and `20c381fbc`† are twins), `99acf1d9f` is trunk (`98639e603`†), `bb5b2e4ae` is trunk
  (`d13f491df`†), `13608cd78` is trunk (`5a673c141`†) and `0375891ac` is trunk (`fa6638ba2`†).
- **"The only revert" (`9d7f3c216`).** It is not on trunk, while the commit it reverts (`d4b7c9ff2`) is. Whether
  trunk later undid `d4b7c9ff2` some other way was not checked by the finders. Skeptic pass: trunk never undid it.
  The `d4b7c9ff2` lines are still in `origin/main:config/kitty.conf` (`rg -c -F`, measured).
- **cc-husk-sweep's COLLECTED for pane 289.** This comes from the brief. It cannot be confirmed from logs, because
  read-only sweep verdicts are not logged. Skeptic pass: confirmed from a transcript. The 0e2799a9 tool_result at
  2026-10-25T01:45:07Z reads `289 7555024a claude4 clean-exit yes dirty COLLECTED watchdog …/Development/personal`.

---

## Skeptic pass

This was an adversarial read-only review on 2026-10-24. It read CENSUS.md, all nine `raw/` files, git, `~/.claude/logs`,
`~/.claude/autonomy` and the four transcript stores. It wrote nothing except this file. Corrections were made in place
above, and each is marked "skeptic pass".

### What was checked

- **Shas (b).** Every 8- and 9-hex token in CENSUS.md (187) was checked with `git cat-file -e`,
  `merge-base --is-ancestor origin/main` and `git log -1`.
  - Every 9-char sha exists except the three already flagged (`10b2c7943`, `cc0f2d205`, `4e150d4a0`). The
    missing 8-char tokens are all session ids.
  - The † marks match.
  - About 30 load-bearing claims were checked against `git show` bodies or diffs, and all of them hold. Examples:
    "ORDINARY SHELL … never an exit" in `4065da386`, "outlived its fix" in `5515ac089`, the pane-76 dry run in
    `d150099dd`, `*"uncommitted change"*` → RESUME in `99acf1d9f`, `--allow-dirty` plus whole-tree `porcelain` in
    `d090b9b56`, and "defer-on-dirty" in `41e3922f8`.
- **Code citations.** At HEAD, gate 3 is `bin/cc-pane-close:489-505`, gate 4 is `:507-511` and the guard is `:520`
  (inside `remote_answers`). `bin/cc-pane-verdict:84-87` maps "fullscreen guard" to DONE and "uncommitted change" to
  RESUME. `bin/cc-husk-sweep` `work_of`/`verdict_of` (:509-518) map whole-cwd dirt to RESUME. All match the census.
- **Logs (c).**
  - §4b weekly incidents were reproduced exactly (W42 = 13), as was the pane-day split since 10-16T22 (61 closed,
    10 rc70, 2 unverified-rc124, 1 rc1, 1 rc67).
  - rc70 = 10 rows. Gate-4 rows = 9, all pane 289 (`pane-close.jsonl` and `pane-close-retry.log`).
  - Fullscreen-guard refusals in `pane-close.jsonl` = 17 (165 ×13, 280 ×2, 282 ×2).
  - Backlog: 32 `husk` ids, every last event `done`. A wider pattern (husk, bare shell, pane-close, self-close,
    fullscreen guard, last pane) gives 121 ids, also all `done`.
  - The watchdog painted "uncommitted work" on 5 panes (460, 369, 463, 85, 289). Only 289 also said "ended
    cleanly", so the census's "dirty cwd caused exactly 1 pane" holds.
- **Coverage (d).**
  - `git log --oneline -i --grep=husk | wc -l` = 139. 91 of them are cited in CENSUS+raw and 52 in CENSUS itself.
    Of the 48 uncited, only 7 have husk in the subject, all tests, docs, fixups or lr-fleet census rows.
  - `rg -l -i husk docs` = 239 files (229 outside this directory).
  - An independent operator-phrase sweep over all four stores (552 files, user-role text, 09-15 on) found 7 operator
    asks. 5 were already in the census and 2 were missing (e284b030, 6d973d05; both added).

### What was corrected

1. **Thesis wording.** `9c0d42af0` ignores untracked files; it is not an own-footprint fix. "Scope (frozen)" is a
   standard brief section (1523 of 1908 [c] top-level transcripts), so it is not husk-specific evidence. The "rising
   every month" claim is a volume effect July–September: 4.7%, 4.3% and 4.7% of trunk commits, then 7.6% in
   October.
2. **Wrong mechanism shas** (each a land tip or test commit cited as the fix):
   - 09-09: `827f2794e`/`37fdc3c1a` → `109cfe4cf` and `2d9d15d2d`.
   - 09-22: `17d522824` (test-only) → `d1bd54c65`, which was authored in 06f6a7f4.
   - 09-28: `c5626280f` (a 5-line operator-readout change, the land tip) → `84218119b` and `360bbbc54`.
   - Twin added: `fc18a0172`† → `1937ed751`. The uncited 9th cc-pane-close trunk commit `eef500138` was named.
3. **Pane 289 causality.** Gate 4 decided the banner and the retry churn, not the outcome. The guard (asked after it)
   would have refused anyway, as it did for 280 and 282 through cc-pane-close the same evening.
4. **Fullscreen class origin.** Sole-FS refusals start 10-16T08:23Z (panes 55, 80, 181), before both `1211646fb`
   (rc70) and the placement commits. So `fd34d855d` did not start the class, and `6fd8c7068` (10-18) is the placement
   birth.
5. **Patched kitty.** "Unverified" became measured: `fsfix:false` on all 977 guard rows 10-16..10-25. Decision
   e3920969aba9's exit condition never held, and 0a8ffe58562a's swap never took effect.
6. **§4c "first and only".** Gate 4 refused pane 76 unlogged on 10-01, before `pane-close.jsonl` began.
7. **§4b denominator.** The 10-02 drop is in close *attempts* of every verdict. A pre-close gate change on 10-01
   explains it as well as the runner does.
8. **Operator counts.** There are 12 sessions, not 9. Only 4 state the two-sided contract, and one 09-20 "hand close"
   was an aborted attempt.
9. **The "operator typed into 289" claim.** The drainer's test is tty atime, which is not proof of typing.
10. **Disagreements now resolved.** COLLECTED is confirmed (0e2799a9, 01:45:07Z), and trunk never undid
    `d4b7c9ff2`.
11. **§6 item 5.** Close-by-own-exit cannot apply to a sole FS pane on stock kitty (the crash trigger), so it
    depends on item 4.
12. **Rows added.** 09-28 e284b030: the operator asked whether a double Ctrl-C should close the pane, and the agent
    recommended keeping the shell (80%). 09-29 6d973d05: rig tabs left open. 10-16: teammate-resurrection, a
    custody actor undoing a graceful close.

### Residual doubts

- **(a) Simpler cause.** The relay thesis is not refuted for July to mid-October, where the dominant code rotated
  (rc124/rc3 → rc67 → rc1/no-registration). From 10-16 the measured majority is one accepted trade-off: the guard on
  stock kitty against an all-fullscreen layout. Whether the relay framing or "a sunset condition that never fired"
  better explains the 10-16 → 10-24 rise is a judgement, not a measurement. The census now states both.
- **Uncovered doc groups.** No finder covered `lr100p-2026-09-19/` (35 husk-mentioning files), `lr-detect-2026-09-19/`
  (27), `lr-reliability-telemetry-speed-2026-10-10/` (8), `voluntary-inplace-switch-2026-09-22/` (5),
  `lr-inplace-immediacy-2026-10-18/` (3), `close-verdict-first-2026-10-10/` (the close-line format that gate 3
  reads), `sigterm-forensics-2026-08-25.md` or `session-durability-2026-10/`. Their file names, a skim of
  teammate-resurrection and the close-verdict-first headline suggest they add limit-recover instances rather than a
  new class. That is estimated, not read.
- **rc124.** Why 12 of 21 pane-289 attempts hit the closer's 60 s bound was not traced. Gates 1-3 call kitty and read
  transcripts, and `eef500138` (10-22) wrapped the closer's relays in `cc-run`. Either could be the cause.
- **Count method.** The §4a "Oct 44" closer-file count re-ran as 45 with month+subject dedup (measured). That
  difference is method, not a contradiction.
- **Recycle path untested.** The recycle-path "Partly" (10-09 → 10-11 row) could not be re-tested.
  `~/.claude/logs/handoffs.jsonl` begins 2026-10-21T14:49Z (rotated) and holds no `recycle-dead` or "bare shell"
  rows (`rg -c`, measured), so it says nothing about 10-11 → 10-21.
