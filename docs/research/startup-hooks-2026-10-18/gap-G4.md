# Gap G4: the drop lines render in panes nobody watches, so a fleet line belongs in #8's acceptance

Read-only. Nothing in the repo or in any account dir was changed. No hook was run. Every scan used `/tmp/startup-hooks-census-files.txt` (411 paths, 402 still present at 14:11Z).

## 1. Verdict

The gap is real, and the measurement here makes it sharper. Two corrections to the proposed fix are needed. (a) The fleet line must not use a "24h" window. A rolling window is a timer, and the line has to clear on acknowledgement. (b) The line must split losses from deferrals, or it reads ⚠ at every start at baseline.

## 2. Measurements

| # | Quantity | Value | Tag / command |
|---|---|---|---|
| 1 | First `entrypoint` per transcript | 359 `cli`, 39 `sdk-cli` (matches the gap text) | [M] `while read f; do jq -r 'select(.entrypoint!=null)\|.entrypoint' "$f" \| head -1; done < /tmp/startup-hooks-census-files.txt \| sort \| uniq -c` |
| 2 | A6 row 4: prompt at launch for 366/383 starts | confirmed at `A6-harness.md:65` | [M] read |
| 3 | First-prompt `promptSource`/`turnOrigin` per transcript | 264 `typed human` (cli), 64 `system task_notification` (cli), 39 `sdk sdk` | [M] jq over first non-meta user record with `.promptSource` |
| 4 | `promptSource: typed` does not mean a person | top first-prompt prefixes repeat across sessions: "Is this all before we clo…" ×30, "[locate] cd /Users/chrisr…" ×29, "no take-backs?" ×26, "Are you sure?" ×24 | [M] jq `.message.content[0:40]` of the first `typed` record, `sort \| uniq -c` |
| 5 | Starts with a startup batch, by class: prompt typed/sdk < 30 s after batch start / no typed prompt at all (system-driven or never prompted) / SDK / **first typed prompt ≥ 30 s after start** | 250 / 94 / 14 / **14** of 372 | [M] inline `python3 -I -` (stdin, not saved): per file, batch start = min(ts − durationMs) over `SessionStart:startup` records; first record with `promptSource ∈ {typed, queued, sdk}` |
| 6 | Starts where a person can be shown to be at the pane (row 5 last class) | 14/372 = 3.8% over 2 d, ≈ 7/day | [M] row 5 |
| 7 | SessionStart `hook_cancelled` by session class (2 d, 56 total) | prompt at launch 23 (dod 10, mailbox 12, setup-task 1) · no typed prompt 13 (mailbox 6, dod 3, dispatcher 3, desk-brief 1) · SDK 13 (mailbox 12, dod 1) · **typed later 7 (dod 2, dispatcher 1 = the incident, foreign/null 4)** | [M] same script, cancels joined to class |
| 8 | Own-hook cancels in a session with a person shown at the pane | **3 of 52 (6%)**. 49 of 52 (94%) have no shown reader, and 13 (25%) are SDK runs, where a person can never see the line | [M] row 7, foreign `null` commands excluded |
| 9 | Dispatcher whole-cancels (D3) in the window | 4: 3 in sessions with no typed prompt, 1 in the incident session | [M] row 7 |
| 10 | SessionStart cancels by day | 22 in the last 24 h (mailbox 17, dod 2, dispatcher 1, foreign 2), 34 in the 24 h before | [M] jq/python over `hook_cancelled` timestamps at 2026-10-18T14:11Z |
| 11 | Operator pulls of the board (`/accounts`) | 2 invocations in 2 d | [M] `rg -c -F '<command-name>/accounts</command-name>'` per census file |
| 12 | The board's renderer is shared | the startup board is the `--readout --narrow` mode of the single renderer `readout_lines` (`bin/claude-accounts:8589`, `:65-67`, `:10379-10381`). The `com.claude.accounts-keepwarm` tick writes it every 180 s (`launchd/staged/com.claude.accounts-keepwarm.plist:61-69`), and `hooks/accounts-board.sh:132-196` only `cat`s it | [M] read |
| 13 | The board hook withholds the whole body once the board is ≥ 1 h old | `accounts-board.sh:176-183` (hard band) | [M] read |
| 14 | statusline | `~/.claude/statusline.sh` is a regular file (not a symlink), byte-identical to repo `statusline.sh` (42,181 B). No `refreshInterval` is set | [M] `ls -la`, `cmp`, `rg refreshInterval ~/.claude/settings.json` |

What this means: the proxy differs from A6's, but the conclusion holds. A per-pane line (#2's systemMessage, #8's first-prompt line) is seen by a person for about 6% of own-hook startup drops. The other ~94% reach the operator only through a surface the operator does look at. The board pull count (row 11) shows that surface is the board rendered at the operator's own starts (about 7/day where a person is shown at the pane [M row 6], plus launch-prompt starts the operator happens to watch [unknown]). It is not a command the operator runs.

## 3. Amended fix: fold a minimal fleet line into #8

**Acceptance criterion added to #8:** "Every own-hook startup drop that the per-pane line cannot be shown to have reached a person is counted on one fleet line. That line renders at every board render, in any session and through `/accounts`, until acknowledged."

Design (each point follows from a measurement above):
1. **Where it renders:** the accounts board, which costs 0 tokens (the top-level `systemMessage`, `accounts-board.sh:4-15`). It sits on the line before the board body, outside the staleness bands. Row 13: a board ≥ 1 h old has its numbers withheld, and drop counts are not a rolling quota, so the fleet line must not be suppressed with them. It carries its own age stamp instead.
2. **Who computes it:** an off-path fold (`cc-startup-health --fleet`) run by the keepwarm tick, which writes `~/.claude/state/startup-health/fleet-line.txt`. The hook adds one `cat`. Folding jsonl inside a 5 s SessionStart hook at ~52 load per core would add a new D2-class victim. The fold reads #8's sentinel/IDL rows (D1, D3, D20) now, and #14's ledger rows (D2, D4, D8, D9) once #14 lands. #8 therefore does not depend on #14.
3. **Clearing:** on acknowledgement, keyed to the occurrence. `cc-startup-health --ack` records the set of occurrence ids (sid + hook + ts) shown at ack time. Any later occurrence raises the line again, and acknowledging never clears by kind (lesson at `.claude/rules/agent-operating-lessons-situational.md:196`; source memory `resolution-signal-must-match-the-occurrence.md`: 27/110 beacons were cleared by the wrong occurrence). **No 24 h window:** "drops 24h" lets an unread drop age out, which is the timer this rule forbids. Count since the last ack, and show the age of the oldest unacked occurrence.
4. **Losses vs deferrals.** At baseline there were 22 cancels in the last 24 h [M row 10], plus about 40 child kills per day [E: A5's ~80 per 2 d, halved] until #1 lands. A single ⚠ total would therefore read non-zero at every start and become wallpaper. ⚠ counts **losses** only: dod-persist cancelled (no DoD), dispatcher cancelled, child killed or cut with owed output, malformed, absent, unproven delivery (D10), commit-then-cancel (D16). Deferrals (a mailbox-drain cancel that committed nothing, or a cancel of a hook that owed nothing) are counted in a plain suffix. Example:
   `⚠ startup losses since ack 10-17 09:12 (oldest 29h): 9 — dod-persist 2, dispatcher 1, child-killed 6 · deferred: mailbox-drain 17 · cc-startup-health --ack`
5. **Ship order:** with or after #1, the same constraint #2 already carries (README.md:32). Before #1 the loss count is about 40+/day [E]. After it, about 6/day [E: dod ~1-9/day from rows 7/10, dispatcher ~1-2/day, residual kills ~3/day from README #1's −95-101 of 107].
6. **Its own failure is loud.** If the fold has not run (file older than 2 keepwarm ticks, or missing), the line says `startup-health fold stale since <t> · cc-startup-health --fleet` and does not disappear. That is the same rule the board applies to itself (`accounts-board.sh:35-43`).

## 4. Drop ledger marking (until Q15 is answered)

Add a column to README §3, "Reaches a person without the fleet line?". Basis: a per-pane line is seen only in shown-watched starts, 14/372 [M row 6].

| Row | Per-pane channel | Mark |
|---|---|---|
| D1 | #8 first-prompt line | **fleet line only** for 49/52 [M row 8]; SDK 13/52 never |
| D2 | #2 dispatcher systemMessage | **fleet line only** for ~96% of starts [M row 6] |
| D3 | #8 first-prompt + outbox board | **fleet line only** (3/4 had no typed prompt [M row 9]). It also cannot render the fleet line in the dropping session itself, because the board is in the cancelled dispatcher, so the next start shows it |
| D4, D5, D7, D8, D9 | #2/#19 systemMessage | **fleet line only** for ~96% [M row 6] |
| D10 | first-prompt line | **fleet line only** |
| D11, D12, D13 | none today | fleet line once #10/#22 write IDL rows; until then not visible anywhere |
| D17 | #8 phase 2 relay + count on the board | already partly fleet; the count joins the same line |
| D18 | per-pane MCP line | per-pane; not a loss (freshness). Leave it off the ⚠ count |
| D20 | statusline (c10 option) | **fleet line** is the no-c10 cover: the operator sees it at their next own start |
| D14, D15, D16, D19, D21 | — | unchanged |

## 5. Ranking effect

| Item | Change | Impact | Effort | Risk | settings.json | Conviction |
|---|---|---|---|---|---|---|
| #8 + fleet line (amended acceptance) | Score unchanged at 2.00 (impact 5 × 0.80 / M), rank 8 kept. The "operator-visible" goal for ~94% of startup drops [M row 8] now rests on rank 8, not on #25/#26 (rank 25-26, 0.60) | Closes D1/D2/D3/D4-D10/D20 for the unwatched ~94-96%. 0 tokens. +1 `cat` (~ms) in accounts-board.sh. Fold off the hook path | +S on top of #8's M | Wallpaper if shipped before #1 or without the loss/deferral split. Producer at PRI 4 can be late (bounded by item 6) | no | 80 |
| #25 | Shrinks to the load-banded span guard; its "cancels by command, ledger drops" half moves to #8 | measurement only | S-M | low | no | 60 |
| #26 | Stays a later refinement (anomaly floors, shadow week) over the same fold | quieter line at baseline | M | low | no | 60 |
| Optional: statusline segment that `cat`s the same `fleet-line.txt` | Shows the line on every refresh of a pane the operator is working in, not only at starts | covers days with few own starts | S (repo `statusline.sh`, deployed as a copy, not a symlink [M row 14]) | statusline runs often under load (docs/research/load-root-cause-2026-10-17/D-hooks-statusline.md); a stat + cat only | no (refreshInterval stays the c10 option) | 55 |

Q15 changes from "operator answer gates the backstop" to "operator answer decides only whether the statusline segment is also wanted". The fleet line ships with #8 whatever the answer.

## 6. Limits

- "Person at the pane" is a lower-bound proxy. Launch-prompt starts the operator watches cannot be told apart in the transcript (row 4), so 3/52 is a floor and 94% a ceiling. The direction of the conclusion does not depend on this.
- The class counts are taken over present files (402 of 411). The census list was not regenerated.
