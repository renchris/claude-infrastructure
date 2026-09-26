# A4 — Effort accounting: Jev, 2026-09-18 → 09-26

## Headline

| Cost axis | Measured | Against |
|---|---|---|
| Jev-primary sessions | **12 transcripts + 37 subagent files** (4 leads, 6 wave teammates, 2 drain/fix) | ~590 on-disk Jev calls (+20 synthetic per lead) |
| Claude tokens (deduped by message.id) | **604.9M total**: 585.9M cache-read, 16.9M cache-create, 2.14M output, 4.2K uncached input | **Jev cost $0** (free window) |
| Input-equivalent (estimated) | **≈90.4M** (weights: cache-create 1.25×, cache-read 0.1×, output 5×) | |
| Lead wall-clock | **73.1 h** (S1–S4); S2→S4 one chain 09-19 04:38Z → 09-22 04:46Z | |
| Commits naming jev | **57, +13,333 / −520 lines** | 0 applied outcomes |
| — fixes of Jev's own infra/tests | **24 (+1,409/−149)**: 24 fixes vs 11 feats; 24 of 54 jev-specific commits = 44% | |
| — feat / docs-research / lessons / test / incidental | 11 (+5,303) / 10 (+5,136) / 8 (+588) / 1 (+29) / 3 (+868) | |
| Operator attention | **40 operator actions**: 24 typed prompts and 16 `<bash-input>` commands the agent handed him (12 of those were jev commands) | |
| — "did we get anything?" prompts | **10** (7 in S3 alone: SCQA ×3, "used Jev ZERO", "how much have we used", "Lead with the answer", "Do what we have to do") | |
| Jev calls after 09-22 03:18Z | **0**. 166 batch ticks logged "no call made" through 09-26, about 3.8 days of free window left unused | |
| Collateral | 5 other sessions hit Jev-caused REDs or flakes. 5 agent-context-sync briefs had to say "DO NOT adopt … JEV DoD" | not in the token total |

Bottom line (measured): about 605M Claude tokens (≈90M input-equivalent, estimated), 57 commits and 40 operator actions bought about 590 free Jev calls. That is roughly **1.0M Claude tokens per Jev call**. 12 of 16 operator commands existed only to run Jev.

## Per-session tokens (measured: `python3 /tmp/jev-pm/a4/tokens.py`, output `/tmp/jev-pm/a4/tokens.txt`)

| Session | Subagent files | cache_create | cache_read | output | total | span UTC | h |
|---|---|---|---|---|---|---|---|
| S1 0f5b9509 at-cost research | 18 | 2.74M | 54.9M | 496K | 58.1M | 09-18 23:09 → 09-19 00:06 | 0.9 |
| S2 09e64dcb /goal integration | 15 | 4.94M | 147.0M | 592K | 152.5M | 09-19 04:38 → 22:35 | 18.0 |
| S3 cb29ae36 pilots/rank | 0 | 1.54M | 110.3M | 248K | 112.1M | 09-19 22:36 → 09-21 05:40 | 31.1 |
| S4 f41a5f25 100p wave + promote | 4 (wave) | 5.04M | 226.0M | 520K | 231.6M | 09-21 05:40 → 09-22 04:46 | 23.1 |
| fed8d9e2 fix jev-promote RED | 0 | 0.17M | 7.6M | 24K | 7.8M | 09-21 15:53 → 16:12 | 0.3 |
| 7a3ac97b re-land predict-land | 0 | 0.33M | 13.3M | 41K | 13.7M | 09-21 09:33 → 16:49 | 7.3 |
| 6 wave teammates (b9644faf etc.) | 0 | 2.14M | 26.7M | 223K | 29.1M | 09-21 05:42 → 06:34 | 0.8 each |
| **Total** | 37 | **16.9M** | **585.9M** | **2.14M** | **604.9M** | | |

S4 is 38% of the total; S3+S4 are 57%.

## Jev calls actually made (measured: `wc -l` / `jq -r .round` on `~/.claude/autonomy/jev-*.jsonl`, batch log grep)

| UTC stamp (filename) | Artifact | Calls |
|---|---|---|
| 09-21 02:22 | jev-pilot | 38 |
| 09-21 02:42 | jev-pilot | 160 |
| 09-21 05:08 | jev-rank | 140 |
| 09-21 16:44 | jev-promote pass 1 | 126 (56 heat + 69 h2h + 1 complete) |
| 09-22 03:09 | jev-promote pass 2 (same seed and corpus: a re-buy) | 126 real + 2 attempt rows |
| 09-22 03:18 → 09-26 | jev-batch.log | 0 calls; 166 "no call made" ticks (`grep -c 'no call made'`) |

On disk: 590 calls. The 20 synthetic calls have no artifact here. No on-disk call predates 09-21 02:22Z, yet 26 of 57 commits had landed by 09-20.

## Commit categories (measured)

Command: `git log -i --grep=jev --since=2026-09-18 --format='@@%h|%ad|%s' --date=short --shortstat`, parsed into `/tmp/jev-pm/a4/commits.txt`. Hand-categorized by subject (`/tmp/jev-pm/a4/cat.txt`), summed with awk. Commits by date: 09-18 1, 09-19 16, 09-20 9, 09-21 26, 09-22 2, 09-23 1, 09-26 2.

- **fix-own (24)** covers the threshold sitting above Jev's output range, the team's own mock being the blocker, status reporting config as liveness, batch/resume loops, promote matching, predict-land fixtures, the 09-26 date bomb, and fleet/parity/test pins broken by Jev landings.
- **incidental (3):** e2d8c9816, cb5f7109c, d9ce5c67b.

## Operator attention (measured: `python3 /tmp/jev-pm/a4/opcount.py`)

Counted: non-isMeta user records minus machine text (notifications, teammate messages, recycle/TASK briefs, auto-continue, bash-stdout).

| Session | Typed | `<bash-input>` | of which jev | Outcome/close questions |
|---|---|---|---|---|
| S1 | 2 | 1 | 0 | 0 |
| S2 | 10 (incl. 3 screenshots) | 0 | 0 | 1 |
| S3 | 10 | 11 | 8 | 7 |
| S4 | 2 | 4 | 4 | 2 |
| **Total** | **24** | **16** | **12** | **10** |

S3 included `bash ~/jev-pilot.sh` four times (one a backtick typo) and `cc-jev rank` twice (the second with `CC_JEV_ZDR=0`). Each call gate became an operator keystroke.

## Collateral (not in the total; whole-session tokens are upper bounds)

- 29490943: Jev arm flake, 11.0M.
- c7ccffe0: cc-fleet pin broken by 82f08302a, 8.2M.
- d90959db: docs land blocked by the jev-promote RED, 128.7M, mostly unrelated work.
- 80d4df03: hook-injected RED.
- 7d062ad1: 09-26 date-bomb fix, 10.9M.

Five agent-context-sync briefs had to say "DO NOT adopt … JEV DoD": the repo-keyed Jev DoD leaked into unrelated sessions.

## Method and classification

- From the 145 listed files, `/tmp/jev-pm/a4/classify.py` measured jev share of assistant text; `brief.py`/`brief2.py` checked first briefs.
- **Primary**: Jev brief or /goal (S1 0.33, S2, S3 0.28, S4 0.23); wave teammates (6 files + S4's subagents = the 10-agent wave); drain/fix briefs naming a jev file (fed8d9e2, 7a3ac97b).
- 7d062ad1 (0.21) had a general brief: collateral. Post-mortem 5714603f excluded.
- Tokens: four usage fields, one record per `message.id` (last line wins), `subagents/**` included.
- Spans: first/last `timestamp`, UTC (mtimes are UTC−5).
- Not measured: weekly-quota share; synthetic-call dates.
