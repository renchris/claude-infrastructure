# Husk-pane history: the Claude Code transcript store (`~/.claude/projects`)

Slice: the jsonl transcripts under `/Users/chrisren/.claude/projects` (`~/.claude-next/projects` is a symlink to
the same directory). Method and coverage are at the end. Git shas were resolved in
`/Users/chrisren/Development/.worktrees/husk-skill-and-fix` (shared history). Times are UTC unless marked CDT.

## Coverage limits (read these first)

- **The store holds only about 30 days.** The oldest top-level transcript was modified on 2026-09-23. Measured with
  `find … -name '*.jsonl' -not -path '*/subagents/*' | xargs stat` sorted by date: 1188 files from 2026-09 and
  719 from 2026-10. Everything before 2026-09-23 (the July–mid-September husk work) survives only in git. The
  pre-window rows below come from `git log` alone.
- **Four other account stores are outside this slice:** `~/.claude-secondary`, `-tertiary`, `-quaternary` and `-next4`
  `/projects` (measured with `ls -ld ~/.claude*/projects`). Some sessions that matter are missing from this store.
  - The pane-289 session `7555024a`: no `*/7555024a*.jsonl` here.
  - The pane-75 fix session `d86e6bd4` (husk-pane-closers).
  - The sessions that wrote `docs/research/lr-stranded-husk-2026-10-10/`, `husk-panes-2026-10-22/REPORT.md` and
    `husk-mass-sigterm-2026-10-21.md`. A search for `"file_path":"…<doc>"` in main-thread files found no writer
    in this store.
- **Hit counts (measured).**
  - The brief's `rg -l` pattern matched 2583 files.
  - Of those, 129 user-role messages matched the pattern (`jq` over string and text-array content). Most were
    workflow-harness subagent briefs, teammate mail, `/limit-recover` skill bodies that quote "husk", and false hits
    on "bare shellcheck".
  - A second symptom-phrase sweep (`close … pane`, `left halfway open`, `in-between state`, `stuck at a shell`,
    and others) over 4136 files found 28 non-sidechain user messages. That sweep is how the operator prompts that
    never use the word "husk" were found. For example, the 2026-10-01 prompt reads "exited out of Claude Code but
    have not closed the pane itself".
- **Duplicates removed.** `03a7cd27` is a resumed copy of `d97e7a14`, with identical messages at 03:14:10.722Z.
  `9aa483e9` is a copy of `09c26b2b`, with identical messages at 05:45 and 16:26. Workflow sidechains share their
  parent's sessionId.

## Operator-typed asks in the window (measured: 4 prompts, 2 shell commands)

| when (UTC) | session | the operator's words (verbatim, trimmed) |
|---|---|---|
| 2026-10-01T03:14:10Z | d97e7a14 (cwd claude-infrastructure) | "Investigate all panes that have been exited out of Claude Code but have not closed the pane itself (ie. not a clean exit; if a session is to recycle/handoff, it should resume into Claude Code, if a session is to close, it should close out that pane entirely)" |
| 2026-10-01T05:30:03Z | d97e7a14 | `!bash /tmp/husk-close-panes.sh --confirm husks`. Output: panes 33, 44, 57, 58, 59 and 60 closed, `verdict=ALL-CLOSED`. |
| 2026-10-01T16:26:14Z | 09c26b2b | Pasted the agent's report ("Kitty's control socket is refusing every connection … Six panes are safe to close by hand now (Cmd+W)"), then asked: "This sounds like a problem that Kitty is blocked from recycling or handoff … Do we need a dedicated /handoff session or self-recycle for this?" |
| 2026-10-01T16:55:31Z | 09c26b2b | `!cc-pane-close --pane 55 --pane 69 --pane 76` |
| 2026-10-10T04:44:21Z | 92928fee (agent-context-sync) | "[Image #1] are we good to close this pane; has this pane been resumed elsewhere?" |
| 2026-10-22T15:55:41Z | e881b713 (kte-w3) | "How come all of these panes are left halfway open (ie. Claude Code session not open but Kitty Terminal pane not entirely closed out) [Image #1]" |
| 2026-10-25T01:42:21Z (10-24 20:42 CDT) | 0e2799a9 (wt-cc-203953-20264) | "Investiate why this pane is in this in-between state (closed sessions should exit out of Claude Code but then also close out the entire Kitty Terminal pane itself; continued/restarted/recycled/handed-off sessions should be working Claude Code) … B) … introspect all of the previous sessions of ours that have asked and worked on this problem" |

The operator restated the same contract three times in 24 days: close means the pane is gone, and continue means
Claude Code is running. The wording barely changed between 10-01 03:14Z and 10-25 01:42Z.

## Chronological table

Source key: OP = operator-typed. BRIEF = a machine brief (HANDOFF-ENGAGE, a "You are …" dispatch, a teammate brief
or a rail-injected prompt). GIT = no transcript in this store, so the row comes from git only.

| when | source | what was asked or claimed | root cause found | change (sha) | recurred? |
|---|---|---|---|---|---|
| 2026-06-09 → 09-22 | GIT (transcripts aged out) | Earlier rounds of the same problem. | Per commit subjects: a pane-close modal (bc5b6d313); "self-close must not orphan a live team, nor leave a husk pane" (4cd42ec45, 07-25); "the agent pane's command is argv, never keystrokes" (4065da386, 08-03); self-close chain measured, "no spawn-side remedy exists" (e46de0942, 08-04); "a pane id it never proved was ours, and a death it never checked" (5515ac089, 08-08); limit-recover `--close-source` "so a transplanted session does not leave a husk behind" (65c612e05, 08-10). | `cc-husk-sweep` born 570c20375 (09-04); the watchdog paints the death verdict into the pane, 810ee9be3 (09-08, desk-husk); 157152995 (09-22). | Yes: every later row. |
| 2026-09-26T21:19Z | BRIEF 798afadf | "Fix four limit-recovery defects … make an in-place limit recovery … end with the session RUNNING in its pane, or a truthful non-RECOVERED verdict." Evidence was pane 780: `recycle-dead`, "never reached a confirmed shell in 6s". | An in-place recovery left the pane at a shell and reported success. | 2e21f81aa "no RECOVERED without proof" (transcript 2026-09-27T07:44Z: `LANDED 2e21f81aa`). | Yes: lr-stranded on 10-10 and lr-wake on 10-18. |
| 2026-09-29T08:56Z / 10:31Z | BRIEF 3c57e64e, 08495bf2 (FLEET_V2 W5a) | The synthetic cohort rig exercises `handoff-fire --husk/--relaunch-at-shell` (6ed411ee0 is referenced). | A husk is now a named state with its own relaunch path. | none in this store (rig wave) | n/a |
| 2026-09-30T00:53Z–02:22Z | workflow sidechain 4104fee7 | The lr-recon W5b README lists "A held husk re-spawned every ~4 s … 181 spawns" (handoffs.jsonl has 181 `recycle-held-bg-work` rows for pane 1316). The lr-handoff report says STRANDED ("tombstoned husk"), but the source was never retired. | The recycle defers on a focused pane, but the report claims retirement. | research only | yes |
| **2026-10-01T03:14Z** | **OP d97e7a14** (copy 03a7cd27) | Close-or-resume contract (verbatim above). Result (assistant, 04:06:34Z): of 39 kitty windows, 7 were at a bare shell (33, 44, 55, 57–60). | (1) Every closer goes through kitty's remote-control socket, which froze for 10–60 s under load, and each closer tried once. (2) The hourly devserver-gc matched "pnpm … dev" in a lead's argv brief and SIGTERMed it (pane 55). (3) For pane 44 after /exit: "Nothing ever closes a pane after Claude exits." (4) The watchdog mislabeled retired teammates "KILLED". (5) `cc-husk-sweep` named the wrong sessions for 57, 60 and 44. Auto mode refused the agent's own close ("Auto mode refused to let me close them"). | 13608cd78 (devserver-gc), 55a2a049e (`docs/research/husk-panes-2026-09-30.md`). The pane-75 fix wave F-a..F-e, by git subject: 74baff1ee ("a clean claude exit closes the pane unless a recycle is pending"), b6bf10c0c, bbc40d207. | **Yes, within 1.5 h.** Assistant at 05:44:49Z: three new husks (55, 69, 76), "the same failure as before … The fix that makes panes close themselves isn't on trunk yet." |
| 2026-10-01T05:45Z → 19:17Z | BRIEF 09c26b2b (copy 9aa483e9: "You are the recycle successor of pane 72 … HANDOFF-ENGAGE-29198-…"), plus the OP asks at 16:26Z and 16:55Z | Collect pane 75's fixes; investigate. | Per `docs/plans/pane-lifecycle-fixes-2026-10-01.md:38`: kitty 610's control socket was **stuck** (128 queued connections, ECONNREFUSED, 59 unreaped zombies), and only a kitty restart clears it. Decision 337e100f5c71 (:39): the operator's own windows closing on /exit stays **off**. | d150099dd `cc-pane-close` was born with **gate 4: "no uncommitted work in the session's cwd"**. Its body records that pane 76 was refused on the very first live dry run "while its cwd held an uncommitted file". Also b6727f1d9; plan ea9055e32; items 0–7 done (f47cb97db); c3d5a71dc, 904fdd205, e44823f02; `docs/plans/kitty-deadlock-recovery-2026-10-01.md` (dc99a63fe). Kitty was restarted at about 18:2xZ by the waiter/supervisor that the operator armed. | yes |
| 2026-10-01T18:51Z | BRIEF edcbfa61 | "scripts/boot-resume.sh must NOT resume a session that retired itself on purpose." Session d86e6bd4 (husk-pane-closers) ran `self-close --terminal`, and boot-resume then resumed it. | One fix (self-close) was undone by another actor (boot-resume) that did not read the self-close marker. | ba04df7b3 (fix); transcript reports `landed at 627f6115a` (the branch tip; test pin). The edcbfa61 summary adds: "my completion note sits in a mailbox nothing reads". | yes (a different actor each time) |
| 2026-10-09T21:14Z | BRIEF 04bfa0e6 (rail-injected) | "Your self-recycle … FAILED (relaunch-write-failed … pane stranded at a bare shell …)". | Typing the relaunch into the pane failed under load (`verdict=echo-unverified`). | The session re-fired with a staged successor. No commit found in this transcript. Related: 6458e9085 (10-09, launch indeterminate). | yes |
| **2026-10-10T04:44Z** | **OP 92928fee** | "are we good to close this pane; has this pane been resumed elsewhere?" The first answer was "Yes … safe to close". At 04:45:25Z the agent reversed itself: "No, don't close pane 168 yet". | Five causes (assistant, 05:10:22Z): (1) the background-work dialog was answered "Move to background and exit", so the process never quit; (2) nothing owns the moved-but-never-started state; (3) four recovery commands refuse each other in a loop; (4) the in-place restart has no draft carry; (5) the rules told the agent to hand the draft back to the operator. | Fired `fire-lr-stranded-husk` (pane 182). Research e67a156e4 → b68fa8a25 ("pane 168 recovered live on next4 by the unattended rail"); 307655279 (10-10). 44091255 (2026-10-11T00:20Z): "Restart the reconciler onto the stranded-husk fix". | yes (lr-wake on 10-18) |
| 2026-10-14 → 10-15 | GIT (teammate 3a331d40 in recycle-fixes is in this store) | After the kitty crash of 2026-10-15, closers must not close the last pane of a native-fullscreen window. | Closing that pane crashes kitty (`docs/research/kitty-crash-2026-10-15/README.md`, cited in the commits). | 265790f36 ("fullscreen guard gates the runners' close-on-exit and a root zsh's exit"), 62372906a (the guard on it2-kitty close, lr-fleet husk close and cc-pane-close SIGHUP), 43e9b1447, ebaece47d. | **This created a new husk class**: a deliberate keep. In pane 289, self-close refused with rc 70. |
| 2026-10-18 → 10-19 | BRIEF 9057bfff (lr-wake Wave H2), 150304ab (teammate `cc-lr` husk pane), 5056b7f3 (Wave G) | "tests/pane-husk-screen.bats … do not run moves …"; the operator's intent is that no session is left with /exit in its box. | Banners on resumed or failed-launch panes were untruthful; `lr-fleet --one` could not be run from a shell. | a0a41b5d1 (cc_say banners plus `tests/pane-husk-screen.bats`, transcript 2026-10-19T22:07Z); 54acfdb98 ("truthful lr-aware banners and a closer that can close the overnight husks"); 7a33cb733 (10-18: a pane that never ran claude closes); e11666b4c. | yes |
| 2026-10-21T20:36Z → 21:34Z | workflow sidechains 551eb39b (parent not in store) | After a reboot, the operator complained: "some windows back open and working … how come we didn't resume ourselves?" | Restore misses on the resume side. | 160bd4cb3 (boot-resume reads to the true cut); 948810da6 (10-21: "a self-close stamp is the session's intent to end"); f6d2418b4 (husk-mass-sigterm doc plus a validate-bash pkill fix). | yes |
| **2026-10-22T15:55Z** | **OP e881b713** | "How come all of these panes are left halfway open". There were 9 panes (windows 92–100). | Each `timeout 15` around `kitty @ launch` in `bin/it2-kitty` (~:286) killed only the client. Kitty opened the pane later, nobody held its id, and `cc-pane-runner` fell back to a shell after 300 s (~:530). "Nothing owns it, so nothing closes it." (assistant, 15:56:20Z) | da0f61ce6 (built by f575f8f8 in orphan-pane-fix: tag at launch, adopt a late pane, a pane with no command closes); lesson 9451c8336. The 9 panes were closed. | yes (same day: panes 85/42/101) |
| 2026-10-22 → 10-23 | GIT plus BRIEFs d7e2a7a8 (Wave A, 2026-10-23T00:10Z) and 22fce1fc (Wave C, 2026-10-23T17:31Z) | A separate operator question in another store: panes 85, 42 and 101 "open with no Claude Code in them" (`docs/research/husk-panes-2026-10-22/REPORT.md:3-4`). | "**a pane's end state has no owner** … act once, paint once, and never revisit" (REPORT.md:18-20). Causes: a misdirected self-close (:32-41); one-shot closes (:42-45); no single final writer for the screen (:48-54); a peer's death never reaches its lead (:55-58). | Plan `docs/plans/pane-end-of-life-2026-10-22.md`. Wave A A1–A7 (f6a21b919). Wave B: 8d69845a0, c820e86f1, 5d0be0366, ab7e82e9f, 21ea2a872, 2c94cf6d8, and **99acf1d9f** (`cc-pane-verdict` born; it maps `*"uncommitted change"*` to `STATE=RESUME`, `bin/cc-pane-verdict` ~:86). Wave C (22fce1fc summary, 2026-10-23T22:52Z): 975dd4d94, 957279537, d29d83843, 7f7b9c293, 03696fdd5, 3f1a77b71, 4cb749ceb, 0375891ac, 920c2dc72, c2ec8c916. C4: "a pane that is its fullscreen window's only pane is held for you" (by design). | **Yes, on 10-24 (pane 289).** |
| 2026-10-24T20:20Z | BRIEF 502bd860 (agent-context-sync lead) | The standard lead brief now says "revive a dead lane in its own pane with `cc-husk-sweep --resume --yes --pane <N>`". | Husks are now an expected, routine state. | — | — |
| **2026-10-25T01:42Z (10-24 CDT)** | **OP 0e2799a9**; BRIEF 06457213 (session B, goal set at 01:51:28Z) | Pane 289 (session 7555024a, transcript not in this store). It said "Good to close: yes", self-close rc 70 (fullscreen guard), cc-pane-close refused 21+ times on gate 4 (138 sibling files in shared cwd `~/Development/personal`), and cc-pane-verdict painted "⛔ resume … stopped mid-task" while cc-husk-sweep said COLLECTED. | Gate 4 (d150099dd) judges **cwd** dirt, not the session's own paths. The verdict mapping (99acf1d9f) turns that refusal into RESUME. The fullscreen guard (265790f36) blocks the self-close. Three components, each correct by its own predicate, add up to a husk with a false banner. | In flight: ab9e2468f (workflow A maps, unlanded at 02:07:19Z per 0e2799a9); 3ebeaf508 (`feat(skills): husk-pane`, in `--all` history). | — |

## Why it keeps coming back (evidence-backed)

1. **Each fix is incident-scoped and closes one mechanism, and many mechanisms reach the same symptom.** Seven
   distinct root mechanisms appear in this window alone:
   - a stuck kitty socket (10-01);
   - a devserver-gc kill (10-01);
   - no close-on-exit (10-01);
   - boot-resume reviving a self-closed session (10-01);
   - an lr move that was never started (10-10);
   - a launch client timeout that orphans a late pane (10-22);
   - a misdirected self-close (10-22).

   On top of these come two deliberate keeps: the fullscreen guard (10-15) and the dirty-cwd gate (10-01). The
   dispatched briefs say "Scope (frozen)" (798afadf, edcbfa61, 22fce1fc), so no wave was allowed to fix the class.
   Measured: `git log origin/main -i -E --grep='husk|pane-close|self-close|…'` gives 430 commits, by month:
   07: 71, 08: 101, 09: 118, 10: 139. The rate is rising, not falling.
2. **The safety gates added for one incident are the next incident's cause, and they fail closed into a husk.**
   - Gate 4 ("no uncommitted work in the session's cwd", d150099dd) refused pane 76 on its very first live dry run
     (commit body). It assumes one session per worktree. Pane 289 ran in a shared checkout with 138 sibling files,
     so the gate could never pass.
   - The fullscreen guard (265790f36, 62372906a) prevents a kitty crash, but by design it keeps the last pane of a
     fullscreen window (Wave C C4: "held for you"). That conflicts with the operator's 2026-10-10 ruling of "zero
     human in the loop" (quoted by the Stop hook in 6788482f at 2026-10-11T00:53Z).
3. **No single owner of a pane's end state, and the readers disagree.** The 10-22 REPORT named this as the common
   root (REPORT.md:18-20), and Wave B added "one writer" (99acf1d9f). But that writer reads the closer's refusal
   *string* (`*"uncommitted change"*` → RESUME, `bin/cc-pane-verdict` ~:86), while `cc-husk-sweep` reads custody
   (COLLECTED, 904fdd205). Pane 289 showed both at once: "⛔ resume" painted beside a sweep that said COLLECTED.
   There is one painter, but still two sources of truth.
4. **Every close is a kitty RPC, and kitty is unreliable at the fleet's normal load.** The evidence:
   - "every call to /tmp/kitty-610 times out at 10 seconds" (d97e7a14, 03:19Z);
   - a socket stuck at 128 queued connections (plan :38);
   - "At load ~450, every attempt … timed out" (e881b713, 15:56Z);
   - "the runner kept the shell. The single close attempt failed, and nothing retried" (REPORT.md:27).

   Fixes keep adding retries and drainers (5d0be0366, C4, C5) instead of removing the dependency.
5. **Each launch path needs its own close-on-exit, and fixes land one launcher at a time.**
   - The plan's decision note says the two panes stuck that day ran "under reso-resume-one's expect and … a
     hand-opened zsh, and neither is cc-pane-runner" (plan :36).
   - 74baff1ee fixed only the runner. reso-resume-one followed in item 6, it2-kitty splits in da0f61ce6, and
     lr-fire-resume and boot-resume paths in other waves.
   - Hand-started windows are kept on purpose (decision 337e100f5c71, plan :39).
6. **Actors undo each other's end states.**
   - Boot-resume resumed a session that had self-closed (edcbfa61).
   - A headless `claude -p` inside a lead's pane self-closed the lead (REPORT.md:32-37).
   - The lr reset poller marked a never-started move "done" (92928fee, 05:10Z).

   Each fix teaches one actor to read one other actor's marker. No shared lifecycle record exists that every actor
   must consult.
7. **The agents themselves are blocked from finishing the close, so husks wait on the operator.**
   - "Auto mode refused to let me close them" (d97e7a14, 04:06Z), and the operator then ran the close script by
     hand (05:30Z) and `cc-pane-close` by hand (16:55Z).
   - The 10-10 agent told the operator to press Ctrl-U (92928fee, 04:56Z).
8. **The institutional memory decays faster than the problem recurs.**
   - Transcripts are kept for about 30 days (oldest 2026-09-23, measured) and split across five account stores.
     Key sessions (7555024a, d86e6bd4, the authors of the lr-stranded-husk report and the 10-22 REPORT) are absent
     from this store.
   - Completion notes can land in "a mailbox nothing reads" (edcbfa61).
   - Each new investigation re-derives the history. The operator's 10-25 ask explicitly requests this census, and
     the 10-01 investigation never cited the 08-04 self-close chain or the 09-04 husk-sweep work.
9. **Tests pin each mechanism in isolation, not the composed path.** Each wave proves its own bats suite with a
   mutant. No suite replayed a whole pane end-of-life across the closer, guard, verdict and sweep. The pane-289
   combination (Good to close: yes, plus a shared dirty cwd, plus the last pane of a fullscreen window) was
   uncovered until the current goal (06457213, 01:51Z) required "the new pane-289 replay bats test".

## Method (reproducible)

1. Ran `rg -l -i -e husk -e 'bare shell' … --glob '*.jsonl'` over the store and wrote the matches to
   `/tmp/huskt/hits.txt` (2583 files).
2. Ran a `jq` pass over user-role messages, using both string content and the text blocks of array content, and
   kept messages matching the pattern: 129 rows in `/tmp/huskt/usermsgs.jsonl`.
3. Ran a symptom-phrase sweep over main-thread messages under 6000 characters, excluding harness, mail and skill
   bodies: 28 rows in `/tmp/huskt/usermsgs2.jsonl`.
4. Per session, read the tail of the assistant text and searched for sha mentions.
5. A commit-line regex (`\[branch sha\]`) found no hits in these main threads. Commits happen inside ship-land or
   worktree subagents, so shas were taken from the assistant summaries and resolved with `git show`/`git log`.
