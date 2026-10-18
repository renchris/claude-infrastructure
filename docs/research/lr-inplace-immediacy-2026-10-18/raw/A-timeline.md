# A — per-session timeline, every batch 2026-10-17T23:57Z..2026-10-18T02:11Z

Source: `~/.reso/limit-recover/move/<batch>/{plan.json,admit.json,<sid>.events.jsonl,<sid>.json,intent/}` and the poller's `MOVE-BATCH started` lines; built by `/tmp/lri-a/timeline.py` (UTC, seconds). `queue` = request → poller start; `admit` = start → admit.json; `wait` = idle wait; `slot` = slot wait; `actuate` = lr-handoff wall time; `prove` = actuated → verdict; `total` = request → verdict. Blank = the stage was not reached. RUNNING = no verdict when read (02:12Z).

| batch | sid | disposition | until | queued | queue | admit | wait | slot | actuate | rc | prove | total | intent left | verdict | reason |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 235745 | 6db28068 | wait:background-job | 3600 | 23:57:45 | 9 | 98 | 3566 |  |  |  |  | 3770 |  | NOTMOVED | still-busy:background-job after 3600s; nothing touched |
| 235745 | 756b68c8 | wait:subagents-in-flight | 3600 | 23:57:45 | 10 | 599 |  |  |  |  |  | 610 |  | NOTMOVED | batch refused: another batch held the admit section for 90s; nothing touched |
| 235745 | 7b50757e | move | 0 | 23:57:45 | 11 | 600 |  |  |  |  |  | 611 |  | NOTMOVED | batch refused: another batch held the admit section for 90s; nothing touched |
| 235745 | 509e3aad | wait:background-job | 3600 | 23:57:45 | 19 | 604 | 3585 |  |  |  |  | 4272 |  | NOTMOVED | still-busy:background-job after 3600s; nothing touched |
| 235746 | 4736324c | wait:background-job | 3600 | 23:57:46 | 26 | 436 | 3570 |  |  |  |  | 4109 |  | NOTMOVED | still-busy:background-job after 3600s; nothing touched |
| 000816 | 43e6eb4b | move | 0 | 00:08:16 | 536 | 6 |  | 0 | 1476 | rc 6 | 673 | 2711 | 339 | NOTMOVED | HELD:unreachable — live in pane 8 on the source, one copy (lr-handoff rc 6) |
| 000922 | 7b50757e | move | 3600 | 00:09:22 | 471 | 12 |  | 0 | 1558 | rc 6 | 593 | 2647 | 4005 | NOTMOVED | HELD:unreachable — live in pane 47 on the source, one copy (lr-handoff rc 6) |
| 002357 | e739e5b5 | move | 0 | 00:23:57 | 23 | 69 |  | 1 | 1910 | rc 6 | 943 | 3034 | 719 | NOTMOVED | REFUSED:not-limited — live in pane 20 on the source, one copy (lr-handoff rc 6) |
| 002443 | 756b68c8 | wait:subagents-in-flight | 3600 | 00:24:43 | 5124 | 17 |  |  |  |  |  |  |  | RUNNING |  |
| 003928 | 381200c5 | move | 0 | 00:39:28 | 4240 | 122 |  |  |  |  |  | 4365 |  | NOTMOVED | claim-held: verdict=held-live sid=381200c5 pid=42086 claim=/Users/chrisren/.reso/limit-recover/runs/by-sid/381 |
| 004329 | ab512c88 | wait:background-job | 900 | 00:43:29 | 4001 | 120 | 899 |  |  |  |  | 5052 |  | NOTMOVED | still-busy:unread after 900s; nothing touched |
| 005330 | 246a91b5 | move | 1800 | 00:53:30 | 3401 | 39 |  | 1 | 8 | rc 6 | 98 | 3702 | -895 | NOTMOVED | REFUSED:intent-invalid — live in pane 1 on the source, one copy (lr-handoff rc 6) |
| 005330 | 04b3cbc3 | wait:background-job | 1800 | 00:53:30 | 3401 | 39 |  |  |  |  |  |  |  | RUNNING |  |
| 005330 | 8db0e6f1 | move | 1800 | 00:53:30 | 3401 | 39 |  | 1 | 4 | rc 6 | 87 | 3693 | -900 | NOTMOVED | REFUSED:intent-invalid — live in pane 24 on the source, one copy (lr-handoff rc 6) |
| 005330 | 381200c5 | wait:mid-turn | 1800 | 00:53:30 | 3401 | 39 |  |  |  |  |  |  |  | RUNNING |  |
| 005330 | e3dedc17 | move | 1800 | 00:53:30 | 3401 | 39 |  | 1 | 5 | rc 6 | 97 | 3702 | -899 | NOTMOVED | REFUSED:intent-invalid — live in pane 201 on the source, one copy (lr-handoff rc 6) |
| 005330 | 2e9ed9f2 | move | 1800 | 00:53:30 | 3401 | 39 |  | 1 | 5 | rc 6 | 88 | 3693 | -899 | NOTMOVED | REFUSED:intent-invalid — live in pane 332 on the source, one copy (lr-handoff rc 6) |
| 005330 | 756b68c8 | wait:subagents-in-flight | 1800 | 00:53:30 | 3401 | 39 |  |  |  |  |  | 3457 |  | NOTMOVED | claim-held: verdict=held-live sid=756b68c8 pid=99147 claim=/Users/chrisren/.reso/limit-recover/runs/by-sid/756 |
| 012244 | 246a91b5 | move | 8134 | 01:22:44 | 1650 | 153 |  |  |  |  |  | 1803 |  | NOTMOVED | claim-held: verdict=held-live sid=246a91b5 pid=38052 claim=/Users/chrisren/.reso/limit-recover/runs/by-sid/246 |
| 012244 | 43e6eb4b | move | 8134 | 01:22:44 | 1650 | 153 |  | 82 | 627 | rc 6 | 68 | 2656 | 7073 | NOTMOVED | HELD:load — live in pane 8 on the source, one copy (lr-handoff rc 6) |
| 012244 | 04b3cbc3 | wait:background-job | 8134 | 01:22:44 | 1650 | 153 |  |  |  |  |  | 1805 |  | NOTMOVED | claim-held: verdict=held-live sid=04b3cbc3 pid=38260 claim=/Users/chrisren/.reso/limit-recover/runs/by-sid/04b |
| 012244 | e739e5b5 | move | 8134 | 01:22:44 | 1650 | 153 |  | 74 | 813 | rc 4 |  |  | 7076 | RUNNING |  |
| 012244 | 4736324c | wait:background-job | 8134 | 01:22:44 | 1650 | 153 |  |  |  |  |  |  |  | RUNNING |  |
| 012244 | 8db0e6f1 | move | 8134 | 01:22:44 | 1650 | 153 |  |  |  |  |  | 1808 |  | NOTMOVED | claim-held: verdict=held-live sid=8db0e6f1 pid=38577 claim=/Users/chrisren/.reso/limit-recover/runs/by-sid/8db |
| 012244 | 381200c5 | move | 8134 | 01:22:44 | 1650 | 153 |  |  |  |  |  | 1808 |  | NOTMOVED | claim-held: verdict=held-live sid=381200c5 pid=42086 claim=/Users/chrisren/.reso/limit-recover/runs/by-sid/381 |
| 012244 | 509e3aad | wait:background-job | 8134 | 01:22:44 | 1650 | 153 |  |  |  |  |  |  |  | RUNNING |  |
| 012244 | 7b50757e | move | 8134 | 01:22:44 | 1650 | 153 |  | 72 | 681 | rc 6 | 119 | 2758 | 7077 | NOTMOVED | HELD:load — live in pane 47 on the source, one copy (lr-handoff rc 6) |
| 012244 | e3dedc17 | move | 8134 | 01:22:44 | 1650 | 153 |  |  |  |  |  | 1809 |  | NOTMOVED | claim-held: verdict=held-live sid=e3dedc17 pid=45363 claim=/Users/chrisren/.reso/limit-recover/runs/by-sid/e3d |
| 012244 | 2e9ed9f2 | move | 8134 | 01:22:44 | 1650 | 153 |  |  |  |  |  | 1811 |  | NOTMOVED | claim-held: verdict=held-live sid=2e9ed9f2 pid=45965 claim=/Users/chrisren/.reso/limit-recover/runs/by-sid/2e9 |
| 012244 | 756b68c8 | wait:subagents-in-flight | 8134 | 01:22:44 | 1650 | 153 |  |  |  |  |  | 1814 |  | NOTMOVED | claim-held: verdict=held-live sid=756b68c8 pid=99147 claim=/Users/chrisren/.reso/limit-recover/runs/by-sid/756 |
| 012244 | 6db28068 | wait:background-job | 8134 | 01:22:44 | 1650 | 153 |  |  |  |  |  |  |  | RUNNING |  |
| 014908 | ab512c88 | move | 8134 | 01:49:08 | 68 | 213 |  |  |  |  |  | 282 |  | NOTMOVED | claim-held: verdict=held-live sid=ab512c88 pid=61594 claim=/Users/chrisren/.reso/limit-recover/runs/by-sid/ab5 |
| 014908 | 76033be2 | move | 8134 | 01:49:08 | 68 | 213 |  |  |  |  |  | 935 |  | NOTMOVED | slot-wait: no move slot freed in 600s (width 4, a fixed count, not a memory limit); nothing touched. Run it ag |
| 014908 | 30c3a88d | move | 8134 | 01:49:08 | 68 | 213 |  | 300 | 708 | rc 1 | 10 | 1370 | 8383 | NOTMOVED | HELD:unknown — live in pane 27 on the source, one copy (lr-handoff rc 1) |
| 014908 | 1bf14662 | move | 8134 | 01:49:08 | 68 | 213 |  | 32 | 194 | rc 6 | 50 | 629 | 8650 | NOTMOVED | HELD:draft — live in pane 33 on the source, one copy (lr-handoff rc 6) |
| 020022 | 246a91b5 | move | 5400 | 02:00:22 | 676 | 37 |  |  |  |  |  |  |  | RUNNING |  |
| 020022 | 8db0e6f1 | move | 5400 | 02:00:22 | 676 | 37 |  |  |  |  |  |  |  | RUNNING |  |
| 020022 | e3dedc17 | move | 5400 | 02:00:22 | 676 | 37 |  |  |  |  |  |  |  | RUNNING |  |
| 020022 | 2e9ed9f2 | move | 5400 | 02:00:22 | 676 | 37 |  |  |  |  |  |  |  | RUNNING |  |
