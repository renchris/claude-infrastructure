# Husk-pane triage, 2026-10-01 (read-only), panes 55 / 69 / 76

Read at about 05:45–06:05Z. No pane, process, tracked file or branch was touched. The kitty reads were
`kitten @ ls` and `get-text` only. cc-husk-sweep ran in list mode only, both the live copy and the
fix/husk-fd branch copy, and that mode exits before its typing section (`[ "$MODE" = resume ] || exit 0`).

## Verdicts

| pane | sid | intended? | stranded work | verdict | evidence |
|---|---|---|---|---|---|
| 55 | c82dd5b9-d22f-4558-af01-5e3f7930fcfe (tertiary, launcher `claude3`; wave-2 lead w2-reso-review) | **No.** Killed mid-task. Its last turn (01:41:54Z) said "Re-pointing the other nine operator rows the same way". The API then dropped at 01:51Z with its /goal still active and a retry pending, and devserver-gc SIGTERMed it at 02:26Z. **Its orchestrator later took the work over:** custody `w2-reso-review` was ABANDONED at 03:59:28Z by pane 38 (session 5fb8968b) with "lead collected its work". The backlog shows that orchestrator re-blocking the S7 rows at 02:43–02:44Z (04203db9c27a, 0f487bba36d4, 1d11d3104208, a87519d6dde5, f043145ef89d, f3b1ddb2972a). | **Two untracked files in ~/Development/claude-private** (local-only repo with no remote; the sibling packets s5/s6 are tracked): `backlog-closeout-2026-10/packets/s7-reso-review-index.md` and `…/s7-reso-review-up.sh`. c82dd5b9 wrote both. Decision `35551116505f` uses the index as its receipt, and row `e4500676528c` points at it. The orchestrator committed other claude-private files but never these (0 mentions of `s7-reso-review` in its transcript). Everything else is clean or owned elsewhere: the bm-w2-reso-review worktree is clean and 0 commits ahead; 420af2f142dd is done (heat-v2-rebased landed). The rebased reso-landing-app `landing-overview-wip` at a18b817f is 5 ahead / 2 behind origin, and its force-with-lease push is the operator's filed row `3b54b15b178e`. | **COLLECT-FIRST**: commit the two s7 packet files in claude-private, then CLOSE. **Do NOT resume.** The orchestrator collected the work and abandoned custody, and a resume would re-arm a live /goal over finished work. Closing the pane does not touch those files; only the scrollback goes. | transcript `~/.claude-tertiary/projects/-Users-chrisren-Development--worktrees-bm-w2-reso-review/c82dd5b9-….jsonl` (tail at 01:41–02:26Z); `cc-custody list --json` (open 00:35:50Z, abandon 03:59:28Z); `~/.claude/autonomy/backlog.jsonl`; `git -C ~/Development/claude-private status --short` |
| 69 | 5ea2497e-1374-458a-9294-7852d7b7a260 (next account, launcher `claude`; teammate `trunk-reds` of lead 918b909f) | **Yes. Its lead retired it.** It sent its final report at 05:25:49Z. The lead sent a shutdown_request at 05:26:29Z ("final report received; lead lands the three commits") and later logged "trunk-reds has exited" (TaskStop 05:35:41Z). Claude printed its ordinary exit text, and the watchdog then painted KILLED/abrupt-unknown (no teammate arm). | **None.** Its 3 commits are content-identical on origin/main (`tests/cc-resume-debt.bats`, `tests/cc-await-ping.bats`, `tests/cloud-return.bats`; lead's land `1343ea87c`, land-verify ✓). The bm-w2-converge-gc and bm-w2-trunk-reds worktrees are both clean, 0 ahead. The open custody `w2-converge-gc` names pane 65 (the live lead), not 69. | **CLOSE** | transcript `~/.claude/projects/-Users-chrisren-Development--worktrees-bm-w2-converge-gc/5ea2497e-….jsonl` (`~/.claude-next/projects` is a symlink to the same file); lead transcript `918b909f-….jsonl` records 1529–1599; `~/.claude/logs/teammate-lifecycle.log:32279-32295` (close rc=124 ×3, damped) |
| 76 | b531a87b-24f6-4794-a07f-768094a30d7a (tertiary, launcher `claude3`; teammate `husk-fa` of fix lead d86e6bd4) | **Yes. Its lead retired it.** It reported F-a done at 05:17:49Z. The lead sent a shutdown_request at 05:18:01Z ("F-a collected"), and Claude printed its ordinary exit text. The watchdog painted it at 05:19:10Z. A close *was* attempted: teammate-auto-shutdown at 00:18:23 local, rc=124 (kitty unresponsive), page damped. The earlier "no close was attempted" is wrong. | **None.** It reported `5a2475b88`, which is on no branch, but the lead re-committed it as `9596e7fd0` on fix/husk-fa (the same change plus the lead's revisions and the mutant line). `refs/wip/husk-fa/LAST` (04:21Z) is an earlier checkpoint that this supersedes. The "unlanded:2" on its banner is the lead's two commits on the shared fix/husk-pane-closers cwd, not husk-fa's. The open custody `fire-husk-fixes` names pane 75 (the live lead d86e6bd4). | **CLOSE** | transcript `~/.claude-tertiary/projects/-Users-chrisren-Development--worktrees-fix-husk-pane-closers/b531a87b-….jsonl`; `teammate-lifecycle.log:32254-32266`; `lead-crash-watchdog.log:54695-54736` |

All three are cc-pane-runner panes (`login … kitten run-shell … -c 'exec "$CC_PANE_RUNNER"'`). Each currently
holds only `/bin/zsh -l -i`. Leads 918b909f (pane 65) and d86e6bd4 (pane 75) are still running.

**How the live cc-husk-sweep reads them today (all wrong):** 55 gets RESUME with launcher `claude`, the wrong
account, and the shell's cwd (lr-fv2-w5b2) instead of the session's. 69 gets RESUME. 76 resolves to the **wrong
sid `ddd6409b`** through the transcript lottery and gets RESUME. A live `cc-husk-sweep --resume` would harm all three.

**Operator line:** the three-pane line is withheld because 55 is not CLOSE. `/tmp/husk-close-panes.sh` exists,
and its usage (`--confirm husks [pane:sid …]`) matches; I read it and did not run it. It re-checks a bare-zsh
foreground and the sid in the title before closing. The two CLOSE panes can go now with:

`bash /tmp/husk-close-panes.sh --confirm husks 69:5ea2497e 76:b531a87b`

Pane 55 joins (`55:c82dd5b9`) once the two s7 files are committed.

## Gaps in F-a..F-d

First, a state finding: **fix/husk-pane-closers does not contain F-a, F-c or F-d.** Its two commits are
`5dcb9e910` (F-e) and `3c458424b` (the self-close half of F-b). The rest lives on unmerged teammate branches:
fix/husk-fa `9596e7fd0`, fix/husk-fb `358f07eb2`+`019725342` (`scripts/lib/pane-close-queue.sh`,
`scripts/pane-close-retry.sh`), fix/husk-fb2 `2a5edddb4`, fix/husk-fc `4bc305913` and fix/husk-fd `08179cf6f`.
The lead's last turn (05:35Z) plans to cherry-pick them "queue-lib-first" as batch 2. Until then
`3c458424b` sources a queue lib that is absent from its own tree, so `sc_noanswer_record` takes its
warn-and-skip branch (`scripts/handoff-fire.sh:1871-1873` on fix/husk-pane-closers), which is fail-safe
but not durable. I read the diffs below on the teammate branches.

1. **F-a does NOT close a retired teammate's pane, so panes 69 and 76 would recur.**
   - Vendor teammates arrive in FILE delivery mode, so `CC_PANE_CMD_INTERACTIVE` is unset and reads 0.
   - The pane 69 scrollback holds the line verbatim: `cd /Users/chrisren/Development/.worktrees/bm-w2-converge-gc && env CLAUDECODE=1 … /Users/chrisren/.claude-284/node_modules/@anthropic-ai/claude-code/bin/claude.exe --agent-id trunk-reds@session-918b909f …`. Pane 76 has the same shape.
   - `_claude_verb` (fix/husk-fa `bin/cc-pane-runner:126-132`) reads the first word `cd`. Evaluated on that exact line it returns rc=1 with an empty verb.
   - `_close_on_exit` (`:148-153`) then returns early because interactive≠1, and `_launch` (`:293`) falls to `_fallback`, which execs the shell, leaving a husk.
   - The `cd … && launcher` close exists only for `CC_PANE_CMD_INTERACTIVE=1` (handoff-fire/lr-lib).
   - The comment at `:216-224` asserts that the teammate verb *is* `claude.exe`. That is refuted by the 2.1.284 launch line, whose verb is `cd`.
   - `tests/pane-close-from-inside.bats:60-99` never feeds the `cd … && env … claude.exe --agent-id` shape in FILE mode, so the suite passes over the gap.
   - Side effect of the same root: `_arm_wedge_watch` (`:249-251`) never arms for teammates either.
   - Fix direction: in FILE mode, accept a `cd <dir> && env [VAR=…]… <claude verb>` shape (or key on `--agent-id` in the line). The exit status is still the session's.
   - Unverified residual: no close record exists for teammates, so whether a retired member exits **0** is not measured. If it exits non-zero, F-a keeps the shell by design, and only F-b's drainer would close the pane.
2. **F-c covers the teammate cases.**
   - I ran `teammate_facts`, extracted verbatim from fix/husk-fc, on the real transcripts. 69 → `1 trunk-reds session-918b909f 1`, 76 → `1 husk-fa session-d86e6bd4 1`. Both reach arm 1.4 (`hooks/lead-crash-watchdog.sh:581-586`) and the "✅ RETIRED … close this pane" banner (`:1448-1452`).
   - 55 → `0 - - 0` (lead), as intended.
   - **Gap: a killed lead whose work is later ruled done still gets "Resume it here".**
     - The banner is painted once, at death. Pane 55 was painted at 02:27:27Z, while the ruling came at 03:59Z.
     - CRASH classes take the `*)` branch (`:1472-1477`, `$resume_crash`).
     - The only "work was collected" arm is `retired_by_desk` (`:273-320`). It keys on a cc-teardown retirement, not on a custody `abandon`/`return` written after the death. Nothing re-reads custody or repaints the pane.
     - F-c as written does not meet "a killed lead whose work is done gets a non-Resume banner". The plan's F-c text never claimed that case, so it is a plan gap, not only a branch gap.
     - Fix direction: a repaint hook on `cc-custody abandon|return` for a target pane whose watchdog painted a CRASH verdict. Alternatively, have the pane-verdict entrypoint consult custody.
   - Minor: jetsam outranks arm 1.4 (`:578`). Under memory pressure, a retired member near a JetsamEvent would read CRASH/jetsam-oom. Its banner still names the lead, not --resume (`:1441-1446`), so the risk is low.
3. **F-d identifies all three correctly** (branch copy, list mode, live panes, source=watchdog):
   - 55 → `c82dd5b9 claude3 … bm-w2-reso-review UNKNOWN`
   - 69 → `5ea2497e claude … TEAMMATE`
   - 76 → `b531a87b claude3 … TEAMMATE`

   That fixes the wrong sid, the wrong launcher and the wrong cwd.
   - **Gap: pane 55 is UNKNOWN, and UNKNOWN is resumed by `--resume`.** See the header at fix/husk-fd `bin/cc-husk-sweep:43-44`, `verdict_of` at `:390-392` (close `-` gives UNKNOWN), and the plan filter at `:469-470` (only TRANSPLANTED, DUPLICATE and TEAMMATE are skipped).
   - F-d reads no custody (0 matches for "custody"). So `cc-husk-sweep --resume` would relaunch c82dd5b9, a lead whose custody its orchestrator abandoned as collected, and re-arm its live /goal.
   - Fix direction: a custody arm in which an `abandon`/`return` naming the pane or sid means DONE or ORCHESTRATED, never resumed.
   - Cosmetic: on a TEAMMATE row, WORK shows the lead's shared-cwd state (76: `unlanded:2`).
4. **F-b (teammate closer) is not a gap here.**
   - At first glance the 5 s TeammateIdle hook budget (`settings.json` timeout=5) looks shorter than the 8 s it2 close bound (`TAS_IT2_TIMEOUT_S`). Both members show `hook_cancelled timedOut 5000ms`.
   - The lifecycle log shows the close leg finishing about 19 s after start (`close FAILED rc=124`, `teammate-lifecycle.log:32279`, `:32264`). On fix/husk-fb, `_queue_close_retry` sits on exactly that rc=124 branch (`hooks/teammate-auto-shutdown.sh` close_and_log), so the durable row would have been written.
   - Separate observation, not a husk cause: an auto-shutdown run removed husk-fa's worktree at 00:16:38 local, while husk-fa was still running a suite (`teammate-lifecycle.log:32236`; husk-fa's report to its lead says the same).
