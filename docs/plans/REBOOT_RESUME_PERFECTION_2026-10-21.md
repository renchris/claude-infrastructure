---
status: in-progress
---

# Reboot resume: sessions pick up as if never restarted (2026-10-21)

Scope (frozen): explain why sessions did not resume their own work after the 2026-10-21 macOS 15.8.1
restart, fix what needs perfecting in the reboot and resume path (landed via /ship), and finish the
lead's post-restart duties (confirm 15.8.1, count resumed sessions, run the #! leak test, record it).

Evidence: `docs/research/reboot-resume-2026-10-21/REPORT.md` (six investigators, each checked by a
skeptic; fixes numbered 1-23 there, cited below as R1-R23). Raw results:
`~/.claude/autonomy/research/reboot-resume-2026-10-21/raw-results.json`. Line numbers in the report
are from main as of 2026-10-21 16:00 CDT; re-grep before editing.

## Phase 0 — orchestration

| Wave | Locus | Owner files (single owner each) | Fixes |
|---|---|---|---|
| T1 classify | S (dispatched session) | `bin/cc-resume-classify.py`, `scripts/lib/restore-note.sh`, `tests/restore-note.bats`, classifier selftests | R1 (classifier half), R2 (promise, unblocked, owner kinds), R3 (mail kind), R6 (`_rn_transcript`), R11, R16 |
| T2 boot-resume | S | `scripts/boot-resume.sh`, `scripts/boot-resume-launch.sh`, `launchd/com.claude.boot-resume.plist`, `tests/boot-resume*.bats` | R1 (cut epoch), R3 (mailbox carry), R4, R5, R7, R8, R9 (heartbeat call), R10, R12, R18, R20 |
| T3 prep and land | S | `scripts/alarm-reboot-prep.sh`, `scripts/ship-land.sh` (R13 phase marker, sweep bound, R15 only), `scripts/handoff-fire.sh` (terminal-intent record only), `bin/cc-backlog` (`--until` only), `tests/alarm-reboot-prep.bats` | R2 (owner file, `--until`), R13, R14, R15, R22, R1 (terminal-intent record) |
| T4 layout and heartbeat | S | `bin/cc-resume-layout.sh`, `scripts/lib/restore-heartbeat.sh`, `bin/cc-sessions`, `scripts/lib/pane-spawn-log.sh`, their bats | R6 (`resume_marks`), R9 (`hb_tick` kitty list, tick duration), R17, R19, R21, R23 |

Every implementation wave is S, the default. Lead: session 551eb39b (this plan's author) collects the
four pings, re-reads the ledger, and recycles after collection; it holds no code.

Merge order: T1, T3 and T4 own disjoint files and land in any order. **T2 lands after T1 and T3**,
because it passes their new inputs (below); it rebases onto them and checks for them by content
(`git grep` on origin/main) before its own land.

Decisions left to the operator, not built: turning off macOS "rearrange Spaces by most recent use"
(`mru-spaces`); FileVault authrestart for plain reboots (already backlog `0822e916af70`); the macOS 27
upgrade (decision `a172a41d0d79`).

## Interfaces between waves (the contract; build to it exactly)

- **Owner session (T3 writes, T2 reads, T1 honours).** `alarm-reboot-prep.sh` writes
  `~/.claude/autonomy/reboot-<date>.owner` holding `$CLAUDE_CODE_SESSION_ID` (one line; never append
  to `.start`, whose single-epoch format boot-resume reads, see the 2026-10-04 W3 P3a-i note in prep).
  `boot-resume.sh` passes it as `cc-resume-classify.py --owner <sid>`; the classifier gives that row a
  wake item of kind `owner`, so it is prompted.
- **Read cut (T2).** `boot-resume.sh` passes the true shutdown cut as `--boot-epoch` (last burst of
  shutdown tombstones, else newest pre-boot record, else `hb_start`), not `hb_start`.
- **RETIRED verdict (T1 emits, T2 acts).** A pending `handoff-fire.sh self-close` tool call, or the
  terminal-intent record T3 writes (`~/.claude/autonomy/self-close-intent/<sid>`, removed on every abort
  path), gives verdict `RETIRED`; boot-resume does not relaunch it and names it in the page.
- **`--until` (T3 writes, T1 reads).** `cc-backlog block <id> --until "<probe>"` stores field `until`
  in the row, carried by `list --json`. T1's classifier runs the probe (bounded, 10 s) for blocked rows
  whose `session` field is the row's session; exit 0 adds a wake item of kind `unblocked`. Absent
  field ⇒ no item (old rows keep working).
- **Mail (T2 moves, T1 reads).** T2 carries each pane's unacked mail to its session with
  `mailbox_migrate` (`hooks/lib/mailbox-pending.sh`) before the layout; T1's `mail` item kind counts
  unacked lines in the session's mailbox, ignoring `cc-await-ping` and `boot-resume` senders.
- The prompt text (`rn_prompt_text`, T1) quotes the promise, the row title, or the mail headline.
  Prompts stay limited to wake verdicts (the 2026-08-24 defect was prompting every verdict).

## Waves

Each wave: build every fix listed in its row to the report's change and test text, add the tests the
report names, run its suites (assert the `1..N` plan line), land through the project-local `/ship`,
content-verify on origin/main, converge with `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`,
then ping the lead.

### T1 classify — DONE (1d9c25e83, 7c59a11e9, c79df4865, b259a9a14)
All six fixes built. Replay of boot-1792609590 at the true cut: 2 INTERRUPTED / 11 WAKE-LOST / 12
AT-REST / 0 UNKNOWN / 1 RETIRED; 5d19ef73 RETIRED, 551eb39b woken (owner, promise), 9240c6a9 woken
(mail). Learning: mail must be carried before the classify step, not merely before the layout, and the
sender filter must strip the `[forwarded:<8>]` prefix.

### T2 boot-resume — DONE (af5eda439, 160bd4cb3)
R1, R3, R4, R5, R7, R8, R9, R10, R12, R18, R20, RETIRED, --owner and R22's boot half. Landed before
T3 by the lead's call (its owner-file read tolerates absence). The new plist needed a launchd reload,
done by the lead 2026-10-21 (row a34be1057707): no Nice, no low-priority I/O, logs in ~/.claude/logs.
Not built: the optional separate restore-heartbeat launchd agent (the in-run heartbeat calls cover it).

### T3 prep and land — open

### T4 layout and heartbeat — DONE (8519389c7)
R6, R9, R17, R19 (census 31 rows in ~1 s at load 322), R21, R23. Not built: a pane-close caller of
the tree refresh, since no owned file sees a pane close (a SessionEnd hook would, which is a
settings.json change). Two cc-resume-layout-desktops cases (20, 21) fail on 20 s wall-clock bounds
under load, identically before T4.
