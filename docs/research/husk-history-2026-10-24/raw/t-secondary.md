# Husk-pane history: the `.claude-secondary` and `.claude-next4` transcript stores

Slice: `/Users/chrisren/.claude-secondary/projects` and `/Users/chrisren/.claude-next4/projects`.
I only read files. The only file I wrote is this one.

## Method and counts

- Step 1 used the brief's `rg -l -i` pattern set across both stores. Measured result: 2320 hit files (`wc -l`). All of them are in
  `.claude-secondary`. The same pattern set found **0** hit files in `.claude-next4` (`rg -l … | wc -l`).
- Step 2 kept user-role string messages that are not `isMeta` and match the patterns. Measured result: 147 messages from
  40 sessionIds (jq extraction into `/tmp/tsec/msgs.jsonl`). Many were false positives: `husky`, `bare shellcheck`,
  and router-label prompts in `e59ca0f6`, `804b08eb` and `4faf391c`.
  The operator's own words almost never contain "husk". So I also ran a second sweep over the whole store with operator
  phrasing: `partially closed`, `partial sessions`, `pane itself still open`, `entire pane`, `lingering panes` and `shell kept for resume`.
  That sweep also covered array-content user messages, which is where image-carrying prompts live.
  It added the two operator prompts that define the problem, `2c5e09dc` and `d03e3361`.
- Step 3 traced commits. `git commit` is always run with `-q` in this store, so the `[branch sha]` regex finds nothing (measured: 0 hits
  in all relevant sessions). Instead I took the `-m "<subject>"` text from each session's Bash `tool_use` commands
  and matched it against `git log --all` (31127 commits, measured) to get the shas. Every sha below appears in
  `git log` of `/Users/chrisren/Development/.worktrees/husk-skill-and-fix`.
- I deduplicated by sessionId. Nine sessions exist here only as subagent sidechains, because their parent is in another store:
  `11569d45`, `f7351f3b`, `b4559c60`, `f6ec3532`, `680eb505`, `b6125384`, `cc1f8d0a`, `186452ed` and `4a70830c`. Those rows quote only the brief.
- Classification. **OPERATOR** means a human prompt or a `<bash-input>` the operator typed. **BRIEF** means a handoff or dispatch brief, or an
  orchestrator-written subagent task. **MACHINE** means a task-notification, teammate message or monitor event.

## Chronological table

| when (UTC) | source | what was asked or claimed | root cause given | change (sha) | recurred? |
|---|---|---|---|---|---|
| 2026-09-19T18:45 to 19:11 | `11569d45` (sidechain only; parent outside slice). BRIEF, designer D2-one-command | Today's `/limit-recover` run: "handoff-fire's watcher gave up after 'no claude process appeared within 90s', leaving a transplanted session with no process: a husk with a tombstone, invisible to any watchdog". Design goal: "any failure … must be visible and named, never a fire-and-forget husk" | A fire-and-forget relaunch. Once the watcher gives up, nothing owns the pane | In slice: `0722e41d3` (docs, wave report). The next day `bb5b2e4ae` (2026-09-20, `lr-fleet --retire-husks`) shipped, but it cannot be attributed from this slice | Yes. Pane 500 on 09-22 |
| 2026-09-22T06:23 | `7c8201f8`, **OPERATOR**. The operator pasted an agent's claim ("Pane 500 is now an unretirable husk … closing it is yours (⌘W)") and added "Why cant you close remotely from here? Seems like a blocker we need to fix." At 06:28 the operator asked "How can we make this more determinsitic behavior rather than recommended behavior that never gets picked up the first time around" | Assistant at 06:25:22: the admission predicate asks whether the session died at a usage-limit error. Pane 500 died at the context ceiling. With no LIMITED status there is no transplant, so no tombstone, so "no admissible self-close class". "The husk is the last of them rather than the problem itself". Also: "W10's HUSK predicate admits only on a transplant lock … the same generator re-emitted in a second verb its own fix cannot reach … 'a ratchet cures one verb of a two-verb class.'" | `a91f10e8b` (`cc-lr` not-LIMITED refusal classifies and routes). `aa51d775d` (post-mortem plus a *design* for a sixth self-close class, `--context-dead`) | Yes. At 07:29:45 the session itself said "Pane 500 remains a live husk … the one thing I could not retire". Only the design of the cure landed |
| 2026-09-22T16:35 to 18:55 | `1a1a6a75` (OPERATOR: voluntary in-place account switch). Subagent BRIEF: "Map every transplant-side rail — lock, tombstone, split-brain, husk, self-close". Team in `bf59244e`, `5093d7f3`, `409a8e12` (MACHINE teammate messages) | `lr-fleet.sh` classifies HUSK only through a transplant lock. A teammate test says "no tombstone means this pane is an ORIGIN, not a husk — REFUSED" (`5093d7f3`, 18:39). `409a8e12` (18:55): "the LIMIT path driven by lr-fleet no longer retires the source at all … a behaviour regression" | The husk and self-close rails are keyed to one cause (LIMIT) and do not generalise to other causes | `b23328cf2`, `c3df6dfdf`, `f860309b8` (docs). The team's code commits were made by the lead in another store | Yes. A regression was found while the fix was still in flight |
| 2026-09-22T23:39 | `06f6a7f4`, BRIEF (`cc-lr upgrade`) | "capacity-admit refused the relaunch AFTER `/exit` ⇒ 3 panes stranded at a bare shell. Probe BEFORE any /exit" | Act-then-check: the session is ended before the next step is admitted | `17d522824`, `3f45bfccf`, `7fa3acb4c` (`lr-upgrade` tests) | Yes. The same shape as 10-24: the session ended at "Good to close: yes", and the close it relied on was refused afterwards |
| 2026-09-23T01:29 | `b6125384` (sidechain), BRIEF (ledger skeptic) | Item `3d9943ec9e87`: "teach bin/cc-limited the HUSK disposition". Evidence: `cc-limited` has "no HUSK disposition" | The census and the husk classifier live in different tools | None (ledger adjudication) | n/a |
| 2026-09-29T06:17 to 12:01 | `84f3533b` (BRIEF, W2b), `967a1469` and `d3649568` (BRIEF, W5a continuation), `fa3d5b74` and `ff4392e4` (MACHINE teammate briefs) | The FLEET_V2 rig left records at `HUSK-RETIRED/no-stub` and `/stub`, with actuators "A then A-husk x2". `fa3d5b74`: "rec.bundle is never set … every A-husk and B spawn gets `--resume-launcher \"\"` and dies DETERMINISTIC". "The watcher's held row is never read … row 9 chose A-husk instead of UNCONFIRM" | The reconciler re-drove husks with the wrong inputs, and records written by one component went unread by another | `18910dd50` (recycle fence, `/exit` read-back, `--recycle --husk`, `--relaunch-at-shell`), `f7723369a` (A-husk resumes from the bundle launcher), `6aaeaa44c` (held row routes a husk to UNCONFIRM), `3cd777ce5`, `9e1c0b7de`, `0bcb55a59`, `43885da3a` and others (full list in the per-session section) | Yes. On 10-20 at 05:41, `1af834a8` (MACHINE monitor event) still showed `769b7294 HUSK-RETIRED/no-stub 8` |
| 2026-10-06T15:51 | `680eb505` (sidechain), BRIEF (decision `a4cb66b32b4b`, `cc-lr move` width) | "Not verified: whether the resume-debt rescue that would relaunch a pane left at a bare shell is live. The reconciler is in observe mode; the rescuer's owner was not traced." | Nobody owns the rescue path, and it is not live | `5b65782f9`, `b87e6da64` (docs) | n/a |
| 2026-10-15T05:15 | `f7351f3b` (sidechain; parent outside slice), BRIEF | kitty crashed at 00:01:27 CDT with SIGSEGV in `-[_NSExitFullScreenTransitionController dealloc]`. One of the suspects was "'Close Pane' on a pane at a bare shell prompt". The closers to guard include `cc-pane-close` | Removing the last pane of a native-fullscreen window crashes kitty | Not attributable in slice. Same window in git: `fd0d17f57` (`kitty-fullscreen-guard`, 10-15 02:02 CDT), `62372906a` and `265790f36` (guard put on every autonomous closer and on close-on-exit) | This guard is the refusal that makes husks. Pane 165 on 10-23 and pane 289 on 10-24 (self-close rc70 from the guard; `1211646fb` 10-16: "self-close pages husk-fs without retrying") |
| 2026-10-20T00:54 to 01:04 | `b4559c60` (sidechain), BRIEF | A right-click "Move to" of the last pane of a fullscreen window "just moves into the desktop and stays there". The guard exits fullscreen, then "the empty windowed husk closes" | A side effect of the fullscreen guard | `0c3607639` (docs). Related: `60c87719f`, `ae020a953` | n/a |
| 2026-10-20T04:50 | `f6ec3532` (sidechain), BRIEF (limit-recover review) | "A pane that is both unclaimed and has kitty deaf for longer than 600 s stays at a bare shell. The session is safe on disk but not running until the reconciler re-drives it." (handoff-fire.sh:4362-4421) | A one-shot relaunch with a bounded wait | None in slice | Yes. On 10-22, "every close is one attempt" |
| 2026-10-21T15:44 | `2c5e09dc`, **OPERATOR**: "investigate and identify the root reason, and if its intended or unintended, that we have a lot of partially closed sessions (ie. Claude Code closed, but pane itself still open)" (5 screenshots) | Assistant at 17:00:51. The kill was unintended: `pkill -f "next start" -P <pid>` on macOS read `-P` as a second pattern, which matched `HANDOFF-PING` in every fired session's launch command. It killed 9 sessions plus 6 teammates at 10:24:42 CDT. "The open panes are intended. A session killed by a signal keeps its shell so you can resume it in place, and the stated policy is 'page, never auto-recover.'" The lead was never told, and the alerts never reached the operator | Signal deaths keep the shell by design. Recovery depends on the operator | `f6d2418b4` (validate-bash quote scanner), `d7d5df709` (`cc-husk-sweep` on the shared allowlist), `3f38e6ee1`. The operator ran `cc-husk-sweep --resume --yes` by hand at 17:02:42. `1817e575` (BRIEF, 16:45) re-landed this work after ship-land failed: "4 of 4 path(s) hold content origin/main LACKS". The two structural options were written up but not built | Yes. The next day |
| 2026-10-22T23:21 to 2026-10-23T08:05 | `d03e3361`, **OPERATOR**: "Investigate these partial sessions, if they need to be resumed/restarted, they should be working in Claude Code, if they should be closed out, the entire pane should have been closed out. Don't just investigate the individual cases but the root reason … long-term fix" | Assistant at 00:11:58: "no single component owns how a pane ends. Several components each look once at the moment of death, act once and paint the screen once, and none of them checks again" (REPORT.md:30-60: self-close identity from env, one-attempt closes, late splits, four screen writers, peer death unseen). "Auto mode wouldn't let me close panes myself", so the operator ran `bash /tmp/husk-panes-close-and-resume-lead.sh --confirm panes-85-42-101` at 01:16:31 | Lifecycle ownership is diffuse | `d576d6633` (research). Wave A: `aea01028e` to `2ba830035`, `8d69845a0`. Wave B (dispatched session `35617ab9`, BRIEF 00:11, plus teammate `686ff2ed`): `5d0be0366`, `99acf1d9f` (`cc-pane-verdict` becomes the one writer), `ab7e82e9f`, `d82aa7860`, `c820e86f1`, `2c94cf6d8`, `21ea2a872`, `85b1d7131`, `7a2becf81`, `d0ef0fcbd`, `f3466586f`, `564a9ab49`, `6ad98363a`, `b5e155596`. Plan: `eaf9393bd`. Claimed at 08:05:24: "Good to close: yes … root causes are fixed and live" | Yes. The same day (next row) |
| 2026-10-23T16:11 to 23:02 | `d03e3361` round 2, **OPERATOR** "Good to close?" with screenshots of panes 165 and 144-147 | Assistant at 17:24:23. The closer reaches kitty through the `it2` shim, which routes to iTerm2 when the caller does not descend from kitty. So "Every automatic close since the waves landed has therefore failed. Yesterday's tests stubbed that check, which hid it." The drainer is starved at background priority. Teammate registrations are unparseable. Self-close rows never expire. Pane 165 is the last pane of a fullscreen window: "no automatic path will ever close it", so the operator pressed ⌘W | The fixes were verified against stubs, not live kitty. The fullscreen layout makes husks permanent | `957279537`, `975dd4d94`, `03696fdd5`, `67b74ef87`, `7fe2ccc90`, `c13ae05f5` | Yes. At 2026-10-24T05:40:58: "kitty has no lingering dead panes. The pane-close queue is empty". The pane-289 incident followed that same day |
| 2026-10-24 (from the brief, not in this store) | pane 289, session `7555024a` | `cc-pane-close` gate 4 refuses on *any* `git status --porcelain` line in the cwd (bin/cc-pane-close ~:509-511, from `d150099dd`, 2026-10-01). `cc-pane-verdict` maps `*"uncommitted change"*` to `STATE=RESUME` (bin/cc-pane-verdict:86, from `99acf1d9f`, the 10-22 Wave B change) | Three components classify independently and disagree. The dirt gate tests the whole cwd, not the session's own paths | Being worked on this branch | n/a |

`7555024a` does not appear in either store (measured: `rg -l '7555024a'` returned no files).

## Per-session notes

- **`7c8201f8`** (`.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/7c8201f8-958d-4b88-af26-bd52244424a4.jsonl`).
  The operator's follow-up at 06:28:03 asked for deterministic behaviour. Assistant at 06:30:34 named three tiers: "prose in a skill description … picked up first time? **no**", a front-door command ("yes — until it refuses"), and a refusal at the act ("always"). The `cc-lr` commit first appeared as `cc0f2d205`. That sha is not in `git log --all` (measured). It landed as `a91f10e8b`.
- **`2c5e09dc`** (`…-wt-cc-104255-99140/2c5e09dc-….jsonl`). Doc: `docs/research/husk-mass-sigterm-2026-10-21.md:10` ("The open pane is intended"),
  `:68` ("Husk design: intended, and where it falls short"). At 17:16:56 the operator asked "Update our allowlist/permissions such that you can run these
  commands as needed without human manual command entry", which produced `d7d5df709`. Raw `kitty @ send-text` was deliberately left off the allowlist.
- **`d03e3361`** (`…-wt-cc-181959-2541/d03e3361-….jsonl`). Round 1 was dispatched as two waves (panes 129 and 130). Round 2 was dispatched as Wave C (pane 188). There are no
  commit outputs in its own transcript: it delegated all commits. The shas come from `35617ab9` and `686ff2ed`, plus the plan
  `docs/plans/pane-end-of-life-2026-10-22.md`. Its subagents read the gate-4 code (`holds $d uncommitted change(s)`, 45 rg hits
  across the session's files, measured) but did not change it. The whole-cwd and own-paths distinction is not discussed in this slice.
- **FLEET_V2 W5 commits** (from `967a1469` and `d3649568`, matched by subject): `5ac4c0022`, `66dc34387`, `1f01469f3`, `5158e164e`, `252ef1b58`,
  `8ef163e0f`, `7f5833490`, `4b5a19843`, `43885da3a`, `98a1a48c2`, `0bcb55a59`, `ea8e5f0ae`, `6b2eaef77`, `0453b43c1`, `deb2dd475`,
  `49956864c`, `bb7273d10`, `8c8827193`, `5526c4f5d`, `fd57b0dc3`.

## Why it keeps coming back (evidence-backed)

1. **Each fix cures the verb of the incident, not the class.** On 2026-09-22 the session named this itself: "the same generator re-emitted in a
   second verb its own fix cannot reach … 'a ratchet cures one verb of a two-verb class'" (`7c8201f8`, 06:25:22). After that, each incident's
   fix targeted that day's trigger:
   - 09-22: the LIMIT-only predicate
   - 10-21: the `pkill` quote parser
   - 10-22: self-close identity and one-shot closes
   - 10-23: the it2 routing and teammate parsing
   - 10-24: the dirt gate and verdict mapping

   None of them installed the invariant the operator stated on 10-22: a pane is either live in Claude Code or closed.
2. **The fail-closed gates add up to a husk.** Each closer has several independent refusal gates, and the safe default of every refusal is
   "keep the shell". The gates are:
   - the fullscreen guard (`fd0d17f57`, plus `1211646fb` "self-close pages husk-fs without retrying")
   - the whole-cwd dirt gate (`d150099dd`)
   - "nothing says session meant to end"
   - custody
   - and before those, LIMIT-only admission

   Any one of them can strand a pane, and no gate's refusal has a second route to an end state.
3. **Classifiers are separate and coupled through strings.** `cc-pane-verdict` derives the state by pattern-matching the closer's refusal
   text (`*"uncommitted change"*` → RESUME, bin/cc-pane-verdict:86, `99acf1d9f`). `cc-husk-sweep` holds its own collected/resume logic
   (`904fdd205`). `cc-pane-close` gate 4 holds a third view. The 10-22 fix gave the *screen* one writer (REPORT.md cause 4) but did not give the *decision*
   one owner. So on 10-24 the closer's refusal reason became the screen's resume instruction while the sweep said "close".
4. **Fixes are verified against stubs, then declared live.** Round 2 found that "Every automatic close since the waves landed has therefore
   failed. Yesterday's tests stubbed that check, which hid it." (`d03e3361`, 2026-10-23T17:24:23).
5. **"Done" is a point-in-time census, not a standing invariant.**
   - 2026-10-23T08:05: "root causes are fixed and live". Round 2 came the same afternoon.
   - 2026-10-24T05:40: "kitty has no lingering dead panes". The pane-289 incident came the same day.

   Nothing re-checks the invariant after the session closes.
6. **The husk is designed to be operator-terminated.** The design says "page, never auto-recover" (`2c5e09dc`, 17:00:51). Agents cannot close
   panes in auto mode ("Auto mode wouldn't let me close panes myself", `d03e3361`, 00:11:58). On 09-22 the agent handed the close back with "closing it is yours (⌘W)",
   and pane 165 needed ⌘W because "no automatic path will ever close it" in an all-fullscreen layout. Each new death path therefore inherits
   "keep shell and page" as its default, and it shows up to the operator as a husk.
7. **The session ends before its pane's fate is admitted.**
   - 09-22: "capacity-admit refused the relaunch AFTER `/exit` ⇒ 3 panes stranded at a bare shell" (`06f6a7f4`).
   - 10-24: the session wrote "Good to close: yes" and exited, and the close was refused afterwards (rc70, then gate 4).

   Once the session is gone, nothing with its context can resolve the refusal.
