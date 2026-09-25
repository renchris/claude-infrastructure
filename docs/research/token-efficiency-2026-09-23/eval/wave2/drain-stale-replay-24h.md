# Stale-forward replay, H = 24 h (measured 2026-09-24 19:10 CDT)

- inboxes scanned: 918; forwarded lines: 4770; older than 24 h at delivery: **3754** (78.7%)
- chars in those lines: 1,985,791 of 2,994,145 forwarded chars; median stale age at delivery 174 h

| kind of stale forwarded line | lines | chars |
|---|---:|---:|
| other | 1373 | 819,878 |
| SUPERVISOR PAGE | 1034 | 317,133 |
| handoff / recycle notice | 910 | 194,437 |
| WAKE-PATH-DOWN/CLASS (watcher notice) | 346 | 580,928 |
| HANDOFF-PING (peer report) | 62 | 48,846 |
| CONTEXT n% FULL | 13 | 5,602 |
| lr-fleet / recovery verdict | 10 | 12,504 |
| custody / completion | 6 | 6,463 |

| sender (top 10) | lines |
|---|---:|
| [claude] | 2851 |
| [cc-await-ping] | 346 |
| [claude-infrastructure-237] | 78 |
| [claude-tertiary] | 47 |
| [claude-secondary] | 37 |
| [wt-1ea55b6ad9f3-52] | 33 |
| [claude-quaternary] | 30 |
| [claude-infrastructure-330] | 18 |
| [claude-infrastructure-541] | 17 |
| [wt-pool-7-129] | 12 |
