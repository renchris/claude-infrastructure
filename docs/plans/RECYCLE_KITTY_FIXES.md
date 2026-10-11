---
status: open
---
# Recycle-on-kitty fixes — implementing the 2026-10-10 root-cause report

Source of every fix, file:line and test: `docs/research/recycle-failures-kitty-2026-10-10/REPORT.md` § Ranked fixes (fix numbers below are that list's). Fix 1 already landed (`0e882c9ac`, another session).

Scope (frozen): implement REPORT fixes 2-9, and fix 10 once its throwaway-pane SIGTERM proof passes. Every fix lands through the project `/ship` with a test that is red before it. `scripts/handoff-fire.sh` has exactly one owning wave at a time.

## Phase 0 — Agent Team Orchestration

**Execution locus per wave:** every wave is **S** (a dispatched session, `handoff-fire.sh --prompt-file /tmp/fire-<wave>.txt --worktree <branch> --notify-back <lead> --goal …`). Each one leads its own teammates if its unit spans 2+ files.

**Task size:** each wave is one task, sized for the 40-150K output band (30-75 min, 3-6 files). W2 and W3 sit at the low edge of the band and are kept separate because they share no file.

| Wave | Fixes | Owns (exclusive) | Branch | Blocked by |
|---|---|---|---|---|
| W1 | 2, 3, 4, 5, 6: honest hold text, unreadable-after-own-/exit as receipted residue, defer only on turn-shaped UNKNOWN (distinct exit code), self-lane last-moment re-read, true deferral wording, screen snapshot on holds | `scripts/handoff-fire.sh`, `tests/handoff-recycle-turn-wait.bats`, `tests/handoff-fire-recycle-custody.bats` | `fix/recycle-kitty-w1-composer-defer` | — |
| W2 | 7b: strand-only banner rung before sweep phase 0a | `scripts/autonomy-sweep.sh` + its suite | `fix/recycle-kitty-w2-sweep-strand-rung` | — |
| W3 | 8: zsh `precmd` successor claim, fork-free when nothing is staged | `scripts/kitty-setup.sh` rc block, `scripts/lib/pane-successor.sh` + suite | `fix/recycle-kitty-w3-precmd-claim` | — |
| W5 | 9: converge the composer-parser copies onto the guarded rule (no dialog-over-empty reads EMPTY) | `scripts/lib/cc-tui.sh`, `scripts/lib/lr-composer-snapshot.sh`, lr_recon `observe.py`, `bin/it2-kitty` composer_state, `scripts/limit-recover/lr-fire-resume.sh` LR_SCREEN_SH + one parity suite. **Not** handoff-fire.sh | `fix/recycle-kitty-w5-parser-parity` | — |
| W6 | 10-gate: throwaway-pane proof that SIGTERM at rest exits like `/exit` (transcript intact, bg shell stopped, staged successor claimed, not classed a crash once a teardown marker exists). Measurement + doc only | `docs/research/recycle-sigterm-proof-2026-10-11/` | `research/recycle-kitty-w6-sigterm-proof` | — |
| W4 | 7a (hf_alarm per-record banner with a short handle, before the push), 8b (no `/exit` under extreme load when the successor cannot be claimed), and 10 (SIGTERM exit) **only if W6 proved it** | `scripts/handoff-fire.sh`, `tests/handoff-alarm-records.bats` + new suites | `fix/recycle-kitty-w4-alarm-load-sigterm` | W1 landed, W6 verdict |

**Spawn order:** W1, W2, W3, W5 and W6 fire in parallel; W4 fires once W1 has landed and W6 has reported.

**Lead context budget and succession point:** the lead (this research session, pane of session `f28815ed`) only writes briefs, collects pings and fires W4. It keeps ≥50% of its window for that. Succession point: if the lead passes 50% before W4 fires, it recycles with this plan as the brief.

**Machine constraint at intake (2026-10-11 00:48 local):** load ≈ 53 runnable/core, i.e. F1's regime. Admission is left to `handoff-fire.sh`'s capacity gate. A refused fire is retried, never forced.

## Wave status

(Each wave appends its landed sha and learnings here when it reports.)

- 2026-10-11 ~07:00Z: W1, W2, W3, W5 and W6 fired on next2 (panes 246, 247, 248, 249, 250), with goals armed and verified.
- **2026-10-11 ~07:05Z, ruling: duplicate program found, which wins.** W1 reported that branch `fix/recycle-gaps-kitty` (lead pane 232; 15 commits at `5c9379107`, unlanded) already implements fixes 2-6, 7a, 7b, 9 and 10 (SIGTERM, `1ac887d20`).
  - **Why it wins:** landing both would put two copies of each mechanism into the same `handoff-fire.sh` functions, and that program is hours ahead.
  - **W1, W2 and W5** stand down unlanded. Each commits its work on its own branch, runs its new cases against the rgk tree and sends the failures (rgk's real gaps) to pane 232.
  - **W3** (fix 8) continues: it is not in rgk's diff.
  - **W6** continues as the independent check of rgk's SIGTERM design.
  - **W4** shrinks to fix 8b (hold `/exit` under extreme load when the successor cannot be claimed). It is offered to rgk's lead, and fires from here only after rgk lands, since rgk owns `handoff-fire.sh` until then.
  - **W5** refused the stand-down, correctly: relayed peer mail cannot override a pane's goal. It lands its parser parity first, and rgk takes trunk's parser at rebase while keeping its own fixtures. rgk's lead (232) agreed. It also agreed to absorb the W1/W2 gap lists and asked that 8b fire after its land.
- **W2 — DONE, unlanded by ruling.** Branch `fix/recycle-kitty-w2-sweep-strand-rung` at `36a68fc68`. Gaps it sent to 232:
  - rgk's tests cannot see the strand rung drifting below phase 0a; W2's overrun-0a test catches it, with a mutant control;
  - the banner says "stranded" for the "/exit did not land" variant;
  - the 200-char handle cut drops the record path first;
  - a desk-seen record is re-bannered.
- **W1 — DONE, unlanded by ruling.** Branch `fix/recycle-kitty-w1-composer-defer` at `c3f0b0abb`. Gaps it sent to 232:
  - **HIGH:** rgk's new exit-readback hold line drops the literal `recycle ABORTED before /exit (held: …)` that `lr-upgrade.sh` `lru_hf_evidence`, `lr-handoff.sh:1933` and `lr_recon/settle.py` parse. Their suites stub the old text, so they stay green while the parse silently misses;
  - no screen witness on `recycle-held-unreadable-static`;
  - fix 2(a) is text only (rgk keeps that deliberately: no keystroke into an unreadable box);
  - the snapshot count is unbounded;
  - a whole-screen checksum is defeated by a ticking row.

### W6 — SIGTERM proof (2026-10-11): fix 10 may be built

Report: `docs/research/recycle-sigterm-proof-2026-10-11/REPORT.md` (sha: `git log -1 --format=%h -- docs/research/recycle-sigterm-proof-2026-10-11/REPORT.md`).

- Nine at-rest runs and one mid-turn run on 2.1.293, each in a throwaway kitty tab, at 44-54 runnable per core. At rest, 9 of 9: exit 143, transcript appended and not truncated, background shell stopped, staged successor claimed with nothing typed, real watchdog row `RECYCLE deliberate-teardown`, window kept.
- **SessionEnd hooks ran in only 4 of 9.** Cause not found (the probe-hook flag and a live inbox watcher were both tested and refuted). Fix 10 must treat SessionEnd as best effort.
- Two changes for the implementation in `1ac887d20` (W4 / `fix/recycle-gaps-kitty`): `HF_EXIT_SIGNAL_GRACE_S` (10 s) is shorter than Claude Code's own 15 s shutdown failsafe, so a slow exit is held as "ignored" and strands the pane, make it 30 s or more; and never stand the inbox watcher down before the signal, because the `asyncRewake` hook's exit starts a turn (measured, run r7).
- Not measured live: the expect resume chain (`reso-resume-one` refused at its capacity gate, exit 9; not overridden). Its 143 handling is code read plus an offline Tcl check.
- Learning: the shell that launched claude sees status 0, not 143, when a successor is claimed, because `cc-close-attrib` execs the successor. Read the close-record for the real code.

### W5 — composer-parser parity (fix 9)

Landed as `fix(composer-parsers): a dialog over the box reads UNKNOWN in every copy` (the sha is in the wave's DONE ping and `git log -- tests/composer-parser-parity.bats`).

- **What changed.** `scripts/lib/cc-tui.sh` gained `cc_tui_box_span`, the one box locator the shell readers share; `cc_tui_composer*` and `lr-composer-snapshot.sh` `lcs_draft_rows` call it. The three readers that cannot source it carry the rule themselves: `LR_SCREEN_SH` (run by expect through `bash -c`), `observe.py` `composer_from_screen` and `bin/it2-kitty` `composer_state` (both Python). `handoff-fire.sh` was not touched.
- **The pin.** `tests/composer-parser-parity.bats` runs the reference and all five copies over one corpus (`tests/fixtures/composer-parity`, the real 2.1.291 slash-menu capture, the two real 2.1.260 dialog captures). Before the fix four copies read EMPTY or `/exit` under a dialog, and `LR_SCREEN_SH` read UNKNOWN under its own `/exit` menu.
- **A partly typed command reads UNKNOWN in the reference too.** A box holding `/e` under a menu highlighting `/exit` is a foreign highlight by `0e882c9ac`'s rule, so `composer_content` returns UNKNOWN there. The reader sweep's S04 row ("ok") was measured at `b68fa8a25`, before that commit.
- **Snapshot replay.** Of the 1,060 files in `~/.claude/logs/composer-snapshots`, 784 are empty; over the 276 with content, three verdicts change, all from a draft to UNKNOWN and none from EMPTY: the win527 teammate panel (cc-tui and observe.py) and a win744 screen where observe.py had read the rows under a `╰──╯` panel edge as a draft.
- **Left as it was (each is a false UNKNOWN or a false draft, so it refuses rather than types).** `LR_SCREEN_SH` and observe.py still need a 12-rule run and miss a labelled top border; `LR_SCREEN_SH` reads plain text, so a faint suggestion reads DRAFT; `lcs_draft_rows` quotes the `Try "…"` placeholder as a row; a slash menu drawn below the box reads UNKNOWN in every copy.
- **The close guard now refuses a pane with a dialog over its box** (`bin/it2-kitty` returns UNKNOWN, exit 67). That is the brief's rule; it means a teardown that meets the background-work dialog leaves the pane open.

### W3 — fix 8, the prompt-hook claim (landed 2026-10-11; `git log --grep 'precmd claim'` for the sha)

- **What landed.** `cc_pane_successor_precmd` in `lib/pane-successor.sh` (the brief's `scripts/lib/` path was a typo), installed by the `cc-kitty-agent-teams` rc block: the block sources `~/.claude/lib/pane-successor.sh` and appends the hook to `precmd_functions`. The gate is `[[ -n $TTY && -e <stage-dir>/${TTY##*/}.cmd ]]`, both evaluated in-process; `take` then applies every existing guard unchanged and `cc_pane_successor_exec` replaces the shell.
- **The rc block now upgrades on content, not on a token.** The old staleness test was "the block lacks `cc-in-kitty`", so the hook would have reached no machine that already ran kitty-setup. `--apply` now splices whenever the block differs from what it would write, and `--check` reports that state as OUTDATED. Measured against the live `~/.zshrc`: the upgrade adds the 8 hook lines and changes nothing else.
- **Because the hook body lives in the symlinked lib, later changes to it need no rc rewrite.** Only a change to the three install lines does.
- **Tests:** `tests/kitty-setup-successor-claim.bats`, 8 cases on a real pty. Red on the pre-fix tree: the claim, the fork control, and both upgrade cases. The no-fork case uses `ulimit -u 1` in the interactive shell, under which any fork prints `fork failed`; its control proves the limit bites when a stage exists.
- **Learnings.**
  - A fixture TTL stamped in `setup()` expired before the prompt: under ~40 runnable per core `kitty-setup.sh` alone took over 2 minutes. The fixture now stamps the stage's age when the shell starts.
  - Not closed by this wave (report objection a): a shell started before the rc change has no hook, so its recycle still revokes and types. Every pane relaunched after the converge has it.
  - Not covered: a `.cmd` left by a SIGKILLed watcher keeps the gate open, so that one pane pays `take`'s forks at each prompt until the next stage replaces the file. No claim can result (nonce, lstart and TTL all refuse).
  - Not tested: operator typeahead at the prompt. It stays in the tty buffer and reaches the successor's composer, the same as with every other consumer; the typed fallback is worse, since typeahead interleaves with the launch line.

### W4 — fix 8b, the load hold (landed 2026-10-11; `git log --grep 'load hold'` for the sha)

- **What landed.** `hf_recycle_load_gate` in `scripts/handoff-fire.sh`, called by `recycle_fire_commit` after the last read and before the resume debt, the SIGTERM exit and the typed `/exit`. It holds as `recycle-held-load` (line `recycle ABORTED before /exit (held: load)`, which every existing hold parser already reads, with the `Re-run:` command) when load per core is above the bound **and** no successor of ours is staged for the pane's tty. A staged successor returns before the load is read.
- **The bound.** `HF_RECYCLE_HOLD_LOAD_PER_CORE`, else ship-land's `CC_GATE_MAX_LOAD_PER_CORE`, else 8 per core (80 on a 10-core box, ship-land's derived ceiling). `0`/`off` and `CC_FIRE_CAPACITY_GATE=off` switch it off; an unreadable load proceeds; a non-numeric bound takes 8.
- **Tests:** `tests/handoff-recycle-load-hold.bats`, 5 cases over the extracted commit with the load reader stubbed (`HF_LOAD_PER_CORE`). Cases 1, 2 and 5 are red on trunk `a60fa9925`; 3 and 4 are controls, and each case has a mutant that turns it alone red.
- **Learnings.**
  - Every suite that drives a recycle pins `CC_FIRE_CAPACITY_GATE=off` (hermeticity lint rule 2), so making that the hold's bypass too keeps all of them off the machine's real load, which sat at 8-11 per core while this was built, above the bound. Without it, any of them that reaches the exit with no stage would have held.
  - Only the gate's own verdict 1 holds. Suites that extract `recycle_fire_commit` without the gate get 127 and proceed as before.
  - Not covered: the deferred self-recycle lane holds with no retry ticket; the session stays alive and the operator (or lr-fleet's HELD re-drive) re-runs it.
