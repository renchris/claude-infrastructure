# Open decisions from the overnight limit-recover incident — re-checked 2026-10-19

Answer: of the nine items this incident raised, five are settled by evidence, one is driven now
(the drain job is unloaded), and four wait on the operator. None of the four is above 90%.

| # | Decision | Recommendation | Conviction | Disposition |
|---|---|---|---|---|
| 1 | Which pane was screenshot #1 (REPORT §5 Q1)? | Pane 332 | 99% | Settled. The 13:12 capture of pane 332 ends `➜ personal git:(master) ✗ : hfv-77512-1-18249`, identical to the screenshot. |
| 2 | The `com.reso.drain-to-next3` LaunchAgent (Q2): keep paused, unload, or keep? | Unload; keep its files | 95% | **Driven.** Wave G (6a5a07063) moved its logic into `lr_recon/drain.py`, now reset-aware, so the agent is a stale duplicate. Its "past the reset" branch kept re-rotating healthy next4 sessions. next3, its target, is at 88% weekly. Undo: `launchctl bootstrap gui/$(id -u) <archived plist>`. |
| 3 | What a recycle answers on the bg-work dialog (Q3, packet 4dce9ca65af4) | — | — | Already actioned by the implementation lead. |
| 4 | Pane 430's close-trial question (Q5, backlog 661a8652d2f6) | — | 95% | Moot: answered yes at 19:03Z on 10-18 (`decisions/q5-pane430.md`). |
| 5 | Was account 2 capped before 09:00Z (Q7)? | No | 97% | Settled (`decisions/q7-next2-cap.md`). The limit line was inherited from next4 in the transcript copy. |
| 6 | Deny agent-installed LaunchAgents and `/tmp` launchers (Q9) | Deny | — | Implemented: validate-bash denies both, and `scripts/checks/launchagent-provenance.sh` pages on any unshipped one (Waves D/E/G). |
| 7 | Three stranded next4 sessions (backlog 87df20238deb, 6d3f1d6cd329, 09123f46c397: "resume stranded session …") | Close the rows; do not resume | 95% | Settled. 40b80c03 was a canary that answered "OK" on 09-29. 6507a980 and a2601c01 were teammates whose last turns (10-10) report committed work and a clean tree. All three cwds have since been removed by worktree GC, so a resume would start in a missing directory. |
| 8 | Close the idle floor-plan session 9f6593c5 (now pane 19) and keep its worktree? (96215788a791) | Close it, keep the worktree | 80% | **Sign-off.** It has done no real work since 10-11 and waits only on the Church floor-plan sign-off, which 8e0ccb1f19ed already tracks. Its transcript stays resumable. What holds it at 80: it is the context-holder for the top customer deliverable on the mission board, and the operator may want it warm for the ruling. |
| 9 | Should cc-lr move replace a launcher-started session (no shell survives /exit) instead of holding it? (56c6862291f2) | Keep the hold | 75% | No change. Only 9f6593c5 has ever hit HELD:no-shell (7 times, `decisions/q6-pane258-and-replace.md`). If #8 closes it, the case disappears. Replace-by-default would move sessions into new panes, against the fixed-layout rule. |
| 10 | Recycle load hold: keep 8/core or raise? (600709c5fe4b) | Raise the commit bound to 24/core now that Wave A has landed; keep the 20/24 hysteresis | 75% | **Sign-off.** 33 of 33 typed relaunches above 8/core submitted first time (`decisions/load-hold-bound.md`). Above ~32/core is unmeasured. |
| 11 | How to install the patched kitty (891ea9e9d0f3) | Stock kitty 0.49.2 now; re-sign the patched build only if the crash recurs | 65% | **Sign-off (permissions).** Stock keeps all 35 privacy grants and needs no sitting, but lacks upstream 7e88f51ed7. The crash guard (fb3edd4ff, 996805060) already prevents the known trigger, and 39 repro attempts never crashed. Re-signing keeps the fix but costs a supervised re-grant sitting. |

Not a decision: pane 47 holds the operator's own unsent reply ("2 and 3").
