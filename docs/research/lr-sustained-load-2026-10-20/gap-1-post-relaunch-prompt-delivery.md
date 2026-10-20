# gap-1: delivering the owed continue prompt after an in-place relaunch

Read-only research, 2026-10-20 (05:00-05:50Z). Live checkout `/Users/chrisren/Development/claude-infrastructure`
at `58885750c`. Live state `~/.reso/limit-recover/`. No pane was typed into, no process was signalled, and no
launchctl or cc-lr mutation was run. The only kitty calls were `it2 session read` (`kitten @ get-text`) on 15
panes. Every number is tagged **[M]** (measured, with the command named) or **[E]** (estimated, with the method
named). Hypotheses are marked **[H]**.

Scripts written for this analysis (all read-only, under `/tmp`):

- `/tmp/gap1_ready_join.py`: joins each bundle's launcher verdict to the nearest sample in `~/.reso/load.jsonl*`.
- `/tmp/gap1_boot.py`: finds the first transcript record the relaunched process wrote.
- `/tmp/gap1_screen.sh`: lr-fire-resume's own `LR_SCREEN_SH`, extracted verbatim from `lr-fire-resume.sh:1240-1386`.
- `/tmp/gap1_screen_probe.sh`: runs that screen program against live panes, timed.
- `/tmp/gap1_expect_timeout.exp`: tests what Expect's `timeout` actually measures.

---

## 0. Answer

1. **The "8 s quiet window" does not exist. It is an 8 s wall-clock deadline that fires once.**
   - The code says otherwise (`lr-fire-resume.sh:1517-1521`: "`timeout` in expect means 'no new output for N
     seconds'"; `:1852`: "The pty has painted nothing for $quiet seconds").
   - In Expect 5.45, `timeout` counts from the start of the `expect` command, and output that matches nothing
     does not reset it [M, `expect -f /tmp/gap1_expect_timeout.exp`: a child printing a line every 1 s against
     `set timeout 3` timed out at **3040 ms**; `man expect`: only `exp_continue` "resets the timeout timer"].
   - So `set timeout $quiet` + `expect {…}` (`:1788-1882`) gives the TUI **8 s from spawn** to paint
     `for shortcuts` or `auto mode on`. Only the menu arms re-arm the clock, through `exp_continue`.
   - The `timeout` arm (`:1850-1880`) has no `exp_continue`. It reads the screen **once** and the block ends.
2. **The quiet arm has never typed a prompt.**
   - Since 10-01 the launcher typed into 63 relaunches. All 63 typed on the READY regex.
   - **0** typed on `READY-QUIET inject`.
   - The other **15** of the 78 prompted relaunches ended `READY-NOT-SEEN` [M, `/tmp/gap1_ready_join.py`;
     state census over `*/bundle-202610*/events.jsonl`].
3. **What fails is the deadline, not the screen read.** The decisive variable is boot time: the gap from
   `relaunch-typed` to the new process's first transcript record [M, `/tmp/gap1_boot.py`].
   - READY-regex runs: p50 **3.6 s**, p90 **5.7 s**, max **7.1 s** (n=63).
   - READY-NOT-SEEN runs: **12 of 15 took ≥ 12.4 s**, up to **111.8 s**.
   - In 3 of today's 3 failures the new process's first transcript activity began only 6-15 s after
     relaunch-typed. For two of them that was 3-5 s *after* the launcher had already given up.
4. **The read is fast and correct. It answers "no usable composer yet", not "kitty timed out".**
   - Every verdict landed 8-10 s after relaunch-typed, so the read itself took ≤ 2 s [M]. A kitty remote-control
     (RC) timeout costs ≥ 15 s (`it2-kitty:97`, `IT2_KITTY_TIMEOUT_S` 15), ×2 with the `--ansi` fallback
     (`lr-fire-resume.sh:1251`).
   - I re-ran the same screen program from a PRI-31 shell at load1 248 (24.8/core). It answered in **0.38-0.69 s**
     and read **EMPTY on 14 of 15 panes, busy ones included** [M, `/tmp/gap1_screen_probe.sh`].
   - Verdicts: 14 UNKNOWN, 1 DRAFT, **0 MENU**.
   - The UNKNOWN note cannot say whether the frame had no box yet or the RC call failed fast. No capture is
     taken on that verdict (§3.3).
5. **The failure rate rises with load because boot time does.** READY-NOT-SEEN by load at the verdict:
   - < 10/core: **4/49 (8%)**;
   - ≥ 10/core: **7/16 (44%)**;
   - two failures at 33.6 and 60.7/core;
   - 4 of 15 failures are unjoinable (no 10-01 load file).

   [M, `/tmp/gap1_ready_join.py`.] Under the operator premise (always ≥ 10/core) this stage fails about
   2 relaunches in 5 [E, the ≥10/core rate applied to the premise].
6. **The fallback chain behind it is exactly the blocked part of the system.**
   - Today 7aae55e1 sat with no task turn until the operator typed `/limit-recover` at 04:55:41Z, **41 min**
     after its relaunch [M, transcript].
   - All 3 of today's READY-NOT-SEEN records are still `RELAUNCHED/UNPROMPTED` at 05:26Z [M, `recon/sessions/*.json`].
   - The running reconciler (pid 51148, started 04:31:18Z) predates `58885750c`.
   - Even after that fix, C needs a second FIRST_TURN admission (`__main__.py:1061,1117`). It also needs a kitty
     write from PRI 20.
7. **A keystroke-free route exists and is already in production elsewhere: the positional prompt on the
   `--resume` argv.**
   - The vendor documents `claude -r "<session>" "query"`.
   - `bin/reso-resume-one:927-944` already spawns `--resume $sid {*}$prompt`.
   - On 2.1.293 it landed as a non-meta `{"kind":"human"}` user record 3 s after spawn. That was after every
     SessionStart hook, and UserPromptSubmit fired on it [M, transcript 04bfa0e6 2026-10-09T21:14:14.941Z].
   - It removes the 8 s deadline, the kitty read, the typing, and C's second admission for every prompted
     relaunch.
   - What it adds: one unmeasured interaction (the resume-return menu, already suppressed by env), the double-prompt
     risk if the relay still types, and argv-visible prompt text.
   - The staged successor is the kitty-free vehicle that carries this launch line. It is not a prompt channel
     itself.
   - The messaging socket (cc-wake transport) is kitty-free, but it delivers an `isMeta` **peer** message, not an
     operator prompt (§4.3).

---

## 1. The stage as built

| Step | Code | Gate it imposes |
|---|---|---|
| Launcher decides the prompt in-pane, before spawn | `lr-launch-<sid>-*.sh` (bundle), `LRP_PROMPT` built from `lr-ingest-verify.sh` output. The 3e929a81 prompt was 1001 chars (`prompt-file` event) | none; **the prompt is fully known before `claude` starts** |
| Spawn with **no** prompt argument | `lr-fire-resume.sh:1693,1695` (`… --resume $sid {*}$xargs`) | n/a |
| Main `expect` with `set timeout $quiet`, quiet = `LR_QUIET_S` default 8 | `:1521`, `:1788-1882` | **G1**: READY regex (`:1107`, `for shortcuts` / `auto mode on`) must match within **8 s of wall clock** (reset only by a menu arm's `exp_continue`) |
| READY arm types: `lr_inject` (paste, then CR after DRAFT-MINE), then the transcript submit probe | `:1837-1849`, `:1883ff` | screen reads for DRAFT-MINE before each CR |
| Timeout arm: one `lr_screen` | `:1850-1880` | **G2**: `it2 session read` → `bin/it2` (`cc-in-kitty` ancestry walk) → `it2-kitty` → `kitten @ get-text --extent all`, 15 s bound, twice (`--ansi` then plain, `:1251`). Must parse **EMPTY** |
| Anything else → `READY-NOT-SEEN`, "prompt NOT typed", `lr_tell` (file + cc-notify) | `:1871-1872` | **G3**: one shot; the block ends, no retry, falls through to drain + `interact` (`:2122`) |
| Reconciler fallback C | `lr_recon/act.py:207-210` (`cc_tui_submit` over the kitty socket, PRI 20 per 07 §0); `settle.launcher_settled` (`settle.py:735`) + `C_GRACE_S` (`__main__.py:59,1204`) | **G4**: FIRST_TURN admission again (`__main__.py:1061`, `:1117-1148`: CPU brake, pacer, probe). **G5**: kitty write from PRI 20 (07 §0: `it2 session list` 1/5 inside 10 s at PRI 20) |
| Last resort | `lr_tell` "Type the prompt by hand in the pane" | **G6**: a human |

This stage is missing from 06 §3's bound inventory. As a bound it is "B17: `LR_QUIET_S` 8 s, wall-clock, one-shot,
no retry". It is also missing from 07 §6's kitty-read table: the launcher's `lr_screen` before typing, and C's
`cc_tui_submit`.

---

## 2. Q1: launcher verdicts since 10-01, joined to load

Method [M]: `python3 -I /tmp/gap1_ready_join.py`. It takes every `*/bundle-202610*/events.jsonl` with a
`relaunch-typed` event and finds the verdict: the first `READY`/`READY-QUIET`/`READY-NOT-SEEN` note, or
`composer-painted`/submit-stage events for a READY-regex inject. The nearest `loadavg[0]` comes from
`~/.reso/load.jsonl*`, with 10 cores. A row whose nearest sample is more than 900 s away is "n/a": no load file
exists for 10-01, and those gaps are 1063-32395 s.

### 2.1 Prompted relaunches (owe a turn), n = 78 at 05:41Z

| Verdict | < 10/core | 10-20 | 20-30 | ≥ 30 | n/a | total |
|---|---|---|---|---|---|---|
| READY regex → typed (`lr_inject`) | 45 | 8 | 1 | 0 | 9 | **63** |
| READY-QUIET → typed | 0 | 0 | 0 | 0 | 0 | **0** |
| READY-NOT-SEEN, screen UNKNOWN | 4 | 4 | 0 | 2 | 4 | **14** |
| READY-NOT-SEEN, screen DRAFT | 0 | 1 | 0 | 0 | 0 | **1** |
| READY-NOT-SEEN, screen MENU | 0 | 0 | 0 | 0 | 0 | **0** |

The READY-regex row is 62 runs in the first join plus 769b7294 at 05:40:40Z. The second script (`/tmp/gap1_boot.py`)
ran after it, and its timing has no load join. The by-load split for that row is therefore [E]: 769b7294's load,
about 8-10/core from `uptime` at 05:49Z, put in the < 10 bucket.

Failure rate by load: **< 10/core 4/49 = 8%**, **≥ 10/core 7/16 = 44%** [M].

### 2.2 The 15 READY-NOT-SEEN runs

`verdict Δ` = verdict ts − `relaunch-typed` ts (1 s resolution). `boot Δ` = first transcript record the new
process wrote − `relaunch-typed` [M, `/tmp/gap1_boot.py`, which prefilters by the minute string and json-parses].

| sid | relaunch-typed (Z) | screen | load/core | verdict Δ | boot Δ |
|---|---|---|---|---|---|
| 89bdedfa | 10-01 20:32:31 | UNKNOWN | n/a | 9 | 21.4 |
| 8e18da3f | 10-01 20:33:19 | UNKNOWN | n/a | 8 | 22.7 |
| f8b54aee | 10-01 21:18:33 | UNKNOWN | n/a | 9 | 6.6 |
| 7aaa93ea | 10-01 22:05:41 | UNKNOWN | n/a | 10 | 12.4 |
| 42097363 | 10-04 04:12:44 | UNKNOWN | 14.1 | 9 | 23.9 |
| b671b47e | 10-04 08:06:34 | UNKNOWN | 7.0 | 8 | 21.5 |
| 42097363 | 10-04 08:18:17 | UNKNOWN | 5.8 | 9 | 111.8 |
| c5cd1b06 | 10-04 08:39:23 | UNKNOWN | 11.1 | 8 | 22.9 |
| 1c0f7f90 | 10-04 17:20:21 | UNKNOWN | 8.2 | 9 | 7.6 |
| ebbc7b61 | 10-10 05:55:09 | UNKNOWN | 4.8 | 9 | 19.5 |
| 3df4b1b4 | 10-11 03:24:13 | **DRAFT** | 16.5 | 9 | 17.6 |
| 0c354704 | 10-18 05:28:25 | UNKNOWN | 60.7 | 9 | 15.1 |
| e80b61f4 | 10-20 04:03:57 | UNKNOWN | 33.6 | 10 | 5.8 |
| 7aae55e1 | 10-20 04:14:38 | UNKNOWN | 10.7 | 10 | 14.8 |
| 3e929a81 | 10-20 05:20:57 | UNKNOWN | 12.5 | 10 | 13.0 |

Boot Δ for the 63 READY-regex runs: p50 3.6 s, p90 5.7 s, **max 7.1 s**, and 12 of 63 over 5 s [M, same
script]. No READY-regex run booted slower than 7.1 s, while 12 of 15 READY-NOT-SEEN runs did. The two
distributions barely overlap: the three overlapping failures are at 5.8, 6.6 and 7.6 s.

**Which part fails.** The **8 s deadline**. The screen read returns in ≤ 2 s (verdict Δ 8-10 against a deadline
that starts about 0-1 s after relaunch-typed). Its answer is consistent with a TUI that has not finished painting
a composer. A kitty RC timeout would put the verdict at ≥ 23 s (8 + 15). None did.

### 2.3 No-prompt relaunches (idle moves), for contrast

READY 33 (26 < 10/core, 6 at 10-20, 1 at 20-30), READY-QUIET 1, no verdict 8 [M, same script]. With no prompt,
"no verdict" costs nothing: nothing is owed.

---

## 3. Q2: what the screen read returned, and why

### 3.1 What UNKNOWN means in `LR_SCREEN_SH`

UNKNOWN is printed by six different exits in `lr-fire-resume.sh:1240-1386`:

1. `LR_IT2` or `LR_PANE` empty (`:1247`). `LR_PANE` = `CC_PANE_ID` or `ITERM_SESSION_ID` (`:1199`), not
   `KITTY_WINDOW_ID`.
2. The read returned nothing (`:1283-1284`): an RC failure or timeout.
3. A `❯` row below the last border (`gb`, `:1310-1311`): a torn or half-painted frame.
4. No border pair, or a box under 2 rows (`:1313`).
5. A selector-shaped `❯` at indent 1-4 above the box (`:1305-1308,1316`).
6. The tall-composer re-read failing its shape checks (`:1330-1355`).

The note keeps only the word (`READY-NOT-SEEN inject "screen reads UNKNOWN …"`). On this verdict the launcher
takes **no** capture (`lr_capture` runs only at CR-UNCONFIRMED, RECR-WITHHELD, UNSUBMITTED and NOT-SUBMITTED:
`:1629,2031,2053,2064`). All 15 bundles have no `screen-*.txt` [M, `ls` of the three 10-20 bundles; the only
narrative is `lr-fire-resume.log`, one line each].

### 3.2 Evidence that it was "not painted yet", not "kitty deaf"

- **Timing [M].** All 15 verdicts were 8-10 s after relaunch-typed. With kitty RC failing slowly, the double
  15 s bound (`it2-kitty:97`, `lr-fire-resume.sh:1251`) would have pushed them to ≥ 23 s.
- **The read works fast at this load from this band [M].** `timeout 250 bash /tmp/gap1_screen_probe.sh 55 38 20
  30 41 32 24 35 2 31 10 118 120 22 26` → 14 × EMPTY, 1 × UNKNOWN (pane 118, which has no live session row),
  0.38-0.69 s each, load1 247.8-249.3, caller PRI 31. Panes 41 and 120 were vendor-`busy` and still read EMPTY.
  So a mounted TUI, idle or mid-turn, parses EMPTY.
- **The same code path worked in the same hour [M].** d7eb73d2 (03:52:41Z), 3d1d988a (05:15:02Z) and db755a94
  (05:16:24Z) were reconciler relaunches on the same kind of panes at 10-13/core. They read DRAFT-MINE
  (`composer-painted … after 1s`) and EMPTY (`SUBMIT-UNMEASURED … screen reads EMPTY 6s after`). So `LR_PANE`, the
  wrapper chain and the socket were working for that population. An empty `LR_PANE` in a single pane is not
  excluded; `ps -E` would not show the relays' environment.
- **The new process had not started its first turn yet [M, transcripts].**
  - 7aae55e1: verdict 04:14:48Z. The first records of the new process (`queue-operation`) are at 04:14:52.765Z,
    and the first user record (peer-mail notification) is at 04:14:53.950Z. That is 5 s *after* the verdict.
  - 3e929a81: verdict 05:21:07Z; first new records at 05:21:09.987Z. 3 s after.
  - e80b61f4: new records from 04:04:02.846Z, then a task-notification user record at 04:04:03.175Z. The session
    was already mid-turn (thinking → assistant 04:04:16.660Z) when the screen was read at about 04:04:06-07.
    cc-wake confirms it at 04:04:13Z: `refused-busy … vendor status is 'busy', not idle (beat=prompt)`
    (`~/.claude/logs/cc-wake.jsonl`). [H] The READY phrase is not painted while a turn runs, and the screen read
    caught a frame mid-repaint. My busy-pane probe says a settled busy frame parses EMPTY, so the UNKNOWN here was
    probably a transient frame.
- **The one DRAFT (3df4b1b4, boot 17.6 s) [H].** At 8 s there was a box with content on screen, but the new
  process had not written anything yet. The most plausible source is the **predecessor's last frame**, still on
  screen. That implies the opposite hazard too: a predecessor frame whose box was empty would parse EMPTY. The
  launcher would then type into a process that has not mounted its composer. This is latent today only because the
  quiet arm has never reached EMPTY (0/78).

### 3.3 Why boots exceed 8 s

Boot Δ is the per-session resume cost scaled by load. 42097363 took 111.8 s at only 5.8/core, so the transcript,
hooks and MCP servers matter as much as load. The axis docs (04, 09) already cover why every process on this box is
slow under 15-40/core. This stage turns that slowness into a **lost prompt**, because a fixed 8 s wall clock races
a boot whose p90 is already 5.7 s on good runs. A **fixed** deadline is the wrong primitive under the operator
premise: it waits too long when idle and gives up too early under load.

### 3.4 What happens after READY-NOT-SEEN (incident sessions)

- `lr_tell` mails the session inbox and says "type by hand". cc-notify → cc-wake was **refused-busy for all 5**
  lr-fire-resume-originated wakes on record (10-11, 10-18, three on 10-20) [M, `grep '"from":"lr-fire-resume"'
  ~/.claude/logs/cc-wake.jsonl`].
- The session boots straight into a notification turn: the stale task ids (e80b61f4) or the peer mail (7aae55e1,
  3e929a81). That turn ends, and the session sits idle with no task prompt [M, transcripts].
- `recon/sessions/{e80b61f4,7aae55e1,3e929a81}*.json` all read `phase RELAUNCHED, substate UNPROMPTED`,
  `updated_at` 05:26:02Z [M, `jq`]. `recon/events.jsonl` has no C spawn for them, and the heartbeat pid 51148
  started 04:31:18Z, before `58885750c` (04:57Z). The commit message says "The running reconciler needs a restart
  to load this."
- 7aae55e1's next task turn came from the operator typing `/limit-recover` at 04:55:41Z [M, transcript
  `{"kind":"human"} <command-name>/limit-recover`], 41 min after relaunch.

---

## 4. Q3/Q4: keystroke-free delivery

### 4.1 (a) The positional prompt of the relaunch argv

**What the vendor says [M, WebFetch https://code.claude.com/docs/en/cli-reference].**

- CLI commands table: "`claude -r "<session>" "query"` | Resume session by ID or name | `claude -r "auth-refactor"
  "Finish this PR"`".
- The `--resume` row: "…a prompt you pass on the command line goes to it as its next turn" (stated for a running
  background session).
- `claude "query"`: "Start interactive session with initial prompt".

**What the installed 2.1.293 binary says.**

- `…/.claude-293/…/claude.exe --help` → `Usage: claude [options] [command] [prompt]` … `prompt  Your prompt` [M].
- The main path folds an agent's `initialPrompt` into the positional prompt variable (`Oe`) before the
  session-restore branch (`Us=Boolean(o.continue||o.resume||…)`) [M, binary offset 201853877 via
  `/tmp/gap1_bin.py`]. I did not trace the REPL submit site through the minified bundle. The behaviour is settled
  empirically below.

**Measured on this box, 2.1.293, production [M].**

- `bin/reso-resume-one:100-106,927-944` ships `--prompt-file` as "`claude --resume <sid> "<prompt>"` submits the
  prompt itself, with no typing into the pane".
  - Pilot 2026-10-05, private tmux: "the transcript gained exactly one user record carrying the nonce and an
    assistant reply within 6 s".
  - `docs/plans/RECYCLE_KEYSTROKELESS_DELIVERY.md` §D4 calls it "the only form proven to drive a turn on resume".
- One production delivery: packet `~/.claude/autonomy/recycle-failed/04bfa0e6-….json`, `attached_at`
  21:14:11Z, `delivered_at` 21:15:28Z. In its transcript:
  - SessionStart `hook_success` ×3, `hook_system_message` ×2 and `hook_additional_context` at
    21:14:14.128-.891Z;
  - **then** the prompt at 21:14:14.941Z, `type:user`, `isMeta:null`, `origin {"kind":"human"}`, `promptId` set,
    `version 2.1.293`;
  - `hook_additional_context UserPromptSubmit` at 21:14:15.450Z;
  - the first assistant record at 21:14:21.445Z.

  Load then was 25-27 (2.5/core) [M, `load.jsonl.20261009`]. **It has not been measured under 15-40/core.** The
  mechanism has no timer in it, so [H] load should delay it, not drop it.

**Gates removed.**

- **G1** (8 s deadline): the CLI submits when it is ready, whenever that is.
- **G2** (kitty read before typing) and every typing artifact: in October these were 26 SUBMIT-RECR,
  9 SUBMIT-UNMEASURED, 4 FAILED:submit and 1 CR-UNCONFIRMED [M, state census], plus the paste-chip-collapse
  family in `lr-fire-resume.sh:1200-1238`.
- **G4/G5/G6** (C's second admission, C's PRI-20 kitty write, the human): the prompt rides the admission the
  relay already redeemed (`gate-admitted … one decision, redeemed once`, e.g. e80b61f4 04:03:54Z), and C has
  nothing left to deliver.
- The submit token stays verifiable by disk alone. `lr_recon/tokens.py:106-119` `find_token` matches a
  `type:user` record carrying the token. `_user_kind` (`:89-103`) classes an `origin.kind:"human"` non-meta record
  as `prompt`, so `nonerror_after` and `prompt_answered_after` read it exactly like a typed prompt.

**Risks added.**

| Risk | Status | Evidence / mitigation |
|---|---|---|
| Resume-return ("resume from summary") menu | **Suppressed at the source, still unmeasured with an argv prompt** | lr-fire-resume exports `CLAUDE_CODE_RESUME_THRESHOLD_MINUTES=999999999` (`:1077-1078`). 2.1.293 still reads it: `aIe` returns null when `be<M`, with `M=a.CLAUDE_CODE_RESUME_THRESHOLD_MINUTES??70`, and is gated on `tengu_gleaming_fair*` [M, binary offset 214762161]. Prior ruling: "an argv prompt may be consumed before the menu or alongside it. It needs a pty test with the menu present" (`docs/research/lr-wake-incident-2026-10-18/e-input-gibberish.md:229`). Also `session-durability-2026-10/C2-skeptic-code.md:163` and `C4-hybrids.md:96`: "UNMEASURED". Keep the expect menu arms (`:1790-1835`) as they are |
| Folder-trust prompt | Pre-seeded; argv interaction **[H]** | The target is seeded per move (`act.py:68-70`, lr-preseed-env.sh), and the trust arm stays. [H] The trust dialog is a pre-REPL setup screen, so the prompt waits behind it. Untested |
| Double prompt | Real if the relay also types | The relay must not type when the prompt went on argv (run it in its `--no-prompt` typing mode while passing argv). It must also not tell a human to "type by hand". C must see the token first (row 5); `tokens.find_token` already does |
| Hooks not loaded | **Refuted for the measured case** | All SessionStart hook attachments precede the argv user record, and UserPromptSubmit fires on it (04bfa0e6, above) |
| Slash head parsed as a command | Real for any prompt starting with `/` | "The CLI DOES parse a slash command out of the initial prompt" (`scripts/handoff-fire.sh:9913-9917`; `docs/plans/GOAL_IN_HANDOFF_METHODOLOGY.md:150-165`). LR prompts start `[limit-recover]` (`LRP_CONT` in the launcher). Keep a `check_slash_head`-style refusal |
| Prompt text in `ps` argv | Known class, already hardened | ~1 KB, holding the sid (bundle path) and the `lrr-` token. Argv parsers already treat prompt text as hostile (`lr-upgrade.sh:222-227` "a positional PROMPT that merely mentions `--effort`"; `bin/claude-accounts:917-919`). Fires already ship positional prompts. Re-check the holder census and `lr_member_guard` |
| Ordering against queued notifications at boot | **[H] unmeasured** | All 3 of today's boots ran a notification turn first. `tokens.py:10-15` already handles "the token and a queued notification land in the same millisecond" (947-e) |
| A relaunch argv replayed later re-submits the prompt | Low **[H]** | The token is per attempt (`lrr-` + 12 hex), so a replay is detectable. lr-upgrade rebuilds argv from flags (`lru_flag`), not the prompt |

### 4.2 (b) The staged successor (`lib/pane-successor.sh`)

The successor is a **launch-line** transport, not a prompt channel. The recycler stages a `.cmd`, and the shell that
regains the pane's tty claims it by `mv` ("Delivery becomes a local atomic rename: load can delay it but cannot fail
it", `:5-10`). A `resume`-mode stage wraps the launcher (`:17-20`).

- **What it removes:** kitty from the *relaunch* (07 §6: 6/6 claimed in the incident). It does nothing for the
  prompt. It cannot write into a running TUI: XNU refuses `TIOCSTI` to a non-ctty caller (07 §6).
- **How it composes with (a):** the staged `.cmd` runs `lr-launch-<sid>-*.sh`, which already builds `LRP_PROMPT`
  before spawn. With (a), the claimed successor spawns `claude --resume <sid> "<prompt>"`. The whole recycle is then
  keystroke-free and kitty-free: SIGTERM exit → atomic claim → argv prompt → transcript oracle. No new successor
  code is needed.
- **Risks:** only those of (a). A refused claim falls back to the watcher's typed relaunch, which carries the same
  launcher and therefore the same argv prompt.

### 4.3 (c) Claude Code's messaging socket (cc-wake's transport)

**Transport [M].**

- `bin/cc-wake:14-20,135-164`: an AF_UNIX connect to `messagingSocketPath` (e.g. `/tmp/cc-socks/21343.sock` in
  `~/.claude/sessions/21343.json`, `version 2.1.293`).
- `settimeout(5)`, an auth frame with `peerToken`, then `{"type":"user","session_id":…,"message":{…},
  "priority":"next"}`.
- No kitty. 27 `sent`, 0 `rc:4` transport failures in `cc-wake.jsonl` (08 skeptic L5).

**How it lands [M, 7aae55e1 transcript 2026-10-19T22:40:02.806Z]:**
`type:user`, **`isMeta:true`**, `origin {"kind":"peer","from":"cc-wake:personal-118","verifiedPeerPid":11278}`, with
the content wrapped as `Another Claude session sent a message:\n…`. The 2026-09-10 research also records
`skipSlashCommands:true` (`docs/research/wake-socket-repricing-2026-09-10.md:33`).

**Gates removed:** G2/G5 (kitty), and G1 if the sender polls the session's own readiness file
(`sessions/<pid>.json`, `status`, `messagingSocketPath`) instead of a clock. It removes C's second admission only if
the relay sends it, not C.

**Risks added.**

- **Authority framing.** The model receives it as a *peer* message ("Another Claude session sent a message"), not
  the operator's prompt. Whether a session acts on "continue the task" from a peer as it would on a user prompt is
  **unmeasured [H]**, and this fleet trains agents to treat peer text as data.
- **The oracle.** `tokens.find_token` has no `isMeta` filter (`tokens.py:106-119`), so it finds the token. But
  `_user_kind` returns None for meta (`:92`), so `prompt_answered_after` never counts it, and the 58885750c row-5
  logic would keep the record UNPROMPTED. That needs a code change.
- **cc-wake itself is the wrong sender.**
  - Its W3 (idle) refused all 5 lr-fire-resume attempts as busy.
  - Its W4 requires unacked mail.
  - Its payload is fixed mail-wake text (`bin/cc-wake:280-283`).

  An LR sender would reuse the transport with its own gates.
- UserPromptSubmit hooks on socket frames: **unmeasured [H]**.
- It needs the new process up and its socket bound: the same boot wait as today, but readable from disk.

### 4.4 Summary

| Route | G1 8 s deadline | G2 kitty read | C's 2nd admission | C's kitty write | Human | New risk |
|---|---|---|---|---|---|---|
| Today (expect READY / one quiet read) | **gate** | **gate** | **gate** | **gate** | **gate** | none |
| (a) argv prompt | removed | removed | removed | removed | removed | resume-menu interaction (env-suppressed, pty test owed); double prompt if the relay also types; slash head; argv text |
| (b) successor alone | n/a | n/a | n/a | n/a | n/a | none, and it delivers no prompt. With (a), the full path is kitty-free |
| (c) socket, sent by the relay | removed (readiness from disk) | removed | removed | removed | removed | isMeta + peer framing; oracle change; hooks unknown |
| (c) socket, as C's transport | removed | removed | **kept** | removed | removed | same as above |
| (d) re-armed expect wait (smallest patch) | replaced by a long bound | **kept** | removed when it succeeds | n/a | removed when it succeeds | still types; stale-frame EMPTY hazard (§3.2) |

---

## 5. Earlier rulings found (Q3)

- **No ruling against argv prompts on resume exists.** The record repeatedly recommends them:
  - `session-durability-2026-10/judge-verdict.md:120` ("The turn arrives as the positional prompt on
    reso-resume-one's spawn line");
  - `C2-skeptic-code.md:158-163` ("A safer delivery path was missed");
  - `C4-hybrids.md:85-98`;
  - `W3-build-plan.md:311-321` (the pilot gate);
  - `RECYCLE_KEYSTROKELESS_DELIVERY.md` §D4.

  RECYCLE_KEYSTROKELESS_DELIVERY.md also notes "lr_recon does NOT [go through reso-resume-one] … lr-handoff.sh and
  lr-upgrade.sh use lr-fire-resume.sh, which spawns `claude --resume` itself" (`:386-388`). **That is the gap.**
- The only open objection: `lr-wake-incident-2026-10-18/e-input-gibberish.md:229` asks for a pty test with the
  resume-return menu present before argv delivery "becomes the default".
- `GOAL_IN_HANDOFF_METHODOLOGY.md` rules on **slash heads**, not argv prompts. The initial prompt is the normal
  fire channel (`launcher "$(cat /tmp/fire-<slug>.txt)"`, `:84-85`). The CLI parses a leading slash command out of
  it (`:155-165`; `handoff-fire.sh:9913-9917`), so a non-`/goal` slash head leaves a task-less pane. That
  constrains the text, not the channel.
- `git log --all -i --grep='positional prompt|argv prompt|initial prompt'` → only the `/goal` built-in docs commits
  (`6cc14dd02`, …) and recycle-100p research [M]. `git log -S'--prompt-file' -- bin/reso-resume-one` →
  `4f912ce85` (W3 P4) and `55bc6fe2e` [M].

---

## 6. Levers

1. **Positional prompt on lr-fire-resume's spawn (a + b).**
   - Pass `$PROMPT` as one trailing argv element on `:1693,1695`, the way `reso-resume-one:927-944` does (absent
     means no element).
   - Run the relay in its no-type mode for that run, and keep the menu, trust and fullscreen arms.
   - Replace READY-NOT-SEEN with a `prompt-argv` note, and keep the transcript submit probe (`LR_PROBE`, kitty-free)
     as the verdict.
   - `settle.launcher_settled` treats `prompt-argv` + `submitted` as the launcher verdict.
   - Gate the rollout on the pty test e-input-gibberish:229 asks for: a private tmux, `LR_RESUME_SUPPRESS=off`, a
     session over the threshold, and a run at ≥ 20/core.
   - Expected effect [E, from §2]: removes the 15/78 READY-NOT-SEEN class (44% at ≥ 10/core) and the typing
     artifacts, and C is no longer needed for prompted relaunches.
2. **Until (1) lands: make the quiet arm a real wait.**
   - On a non-EMPTY verdict, `exp_continue` with a wall-clock bound (≥ 180 s; boot Δ reached 111.8 s).
   - Better: before reading the screen, wait for the spawned pid's own `sessions/<pid>.json` (status +
     `messagingSocketPath`, written by Claude Code, kitty-free) as the readiness oracle.
   - Correct the false comments at `:1517-1521` and `:1852`.
   - Take an `lr_capture` at READY-NOT-SEEN so UNKNOWN can be split from RC failure.
3. **Do not charge C a second first-turn admission for a turn whose admission the relay already redeemed.** Exempt
   `RELAUNCHED/UNPROMPTED` records whose bundle shows `gate-admitted` from FIRST_TURN (`__main__.py:1117`), or
   re-use the same token. Restart the reconciler so `58885750c` is live; the commit message says this is required.
4. **If a post-boot channel is still wanted, use an LR-specific socket sender, not cc-wake, and not C over kitty.**
   - Reuse the cc-wake transport, with LR's own gates and the `lrr-` token in the text.
   - Teach `tokens.py` that a meta peer record carrying this attempt's token is ours.
   - First measure that a session acts on a peer-framed "continue".

---

## 7. Open questions

1. **The resume-return menu.** With the menu forced on (`LR_RESUME_SUPPRESS=off`), is the argv prompt held until the
   dialog resolves, or is it consumed by it? The same question applies to the folder-trust prompt. A pty test is
   owed.
2. **Ordering at boot.** Does the argv prompt run before or after queued task-notifications and peer mail? All 3
   boots today ran a notification turn first.
3. **Argv under load.** Delivery has been measured only at 2.5/core: the pilot and n=1 production delivery. It needs
   a measurement at 15-40/core.
4. **The cause of each UNKNOWN.** Per run, was it a frame with no box, a torn frame, or a fast RC failure? No capture
   was taken. Was `LR_PANE` empty in any of these panes? `ps -E` does not expose the relays' environment.
5. **The stale-frame hazard.** Can the predecessor's last frame parse EMPTY and license typing into an unmounted
   TUI? The 3df4b1b4 DRAFT suggests the old frame is what gets read.
6. **The socket channel.** Do UserPromptSubmit hooks fire for socket frames? Does a session act on a peer-framed
   continue the same way it acts on a user prompt?
