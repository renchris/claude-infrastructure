# A01 — SKEPTIC review of "Stop-hook timeout decay"

Wave: exhaustive-drive 2026-09-08. Read-only. Re-measured 2026-09-08 ~18:28-18:35 local, load avg 74-97 on 10 cores
(higher than the axis run's 16-22 baseline, comparable to its 44-132 wrap-ledger run).
Scratch artifacts: `/private/tmp/claude-501/-Users-chrisren-Development-claude-infrastructure/b418b97a-d3ec-4444-b993-4f29d55f425a/scratchpad/a01s/`
(`trace.txt`, `trace-reso.txt` = PS4-timestamped `bash -x` traces; `cancels.tsv` = re-run census, 7,196 rows).

## Verdict in one line

The census is real and reproduces (4,941 Stop-hook timeouts in 30 d; operator-readout 2,915, completion-assert 1,392;
size-at-kill p50 2.6 MB), the binary suppressions are real, and "not transcript size" holds. **But the root cause the
report names is wrong.** `dod_lineage_ancestors` costs 0.17 s standalone (0.35 s for both calls), not the ~12 s the report
attributes to it; the 14.3 s claude-infrastructure figure did not reproduce (2.15-2.55 s ×4 runs); and the per-cwd spread
is not lineage depth but **which rungs the ledger reaches** — a CLEAN tree (✅) runs `cc-backlog list --blocked`,
`cc-backlog list --all` and `cc-decide list` (1.5 + 1.7 + 1.2 s = 4.4 s of 5.7 s in reso-web-app), a DIRTY tree (🔧)
short-circuits them (`YOURS_SRC=skip`). Two amplifiers the report missed make those numbers reach the 5 s/10 s budgets:
the `_bounded` wrapper is a **no-op** in hook context (`timeout` is not on the Claude process PATH), and the memo's
single-flight degrades to **five concurrent full computes** at every Stop because the winner (2-6 s) always outruns the
750 ms wait ladder — measured 8.0-8.6 s per consumer in reso-web-app, 3.7-5.0 s in claude-infrastructure.

## Numbers re-run

| claim | report | re-measured (command) | holds |
|---|---|---|---|
| Stop timedOut kills 30 d, 4 roots | 4,839 | **4,941** — python scan of 6,215 `*.jsonl` (mtime ≤30 d) for `attachment.type==hook_cancelled`, 12.8 s | yes (Δ = a few hours more data) |
| operator-readout kills | 2,873 | **2,915** | yes |
| completion-assert kills | 1,381 | **1,392** | yes |
| size-at-kill p50 opread / compl | 2.51 / 2.47 MB | **2.62 / 2.59 MB**; max 51.0 / 30.7 | yes |
| goal-inert-watch p50 at kill | 90.8 MB, n=5 | **95.3 MB**, n=5, max 119.6 | yes |
| wrap-ledger --machine uncached, claude-infrastructure | 14.38 / 14.27 s | **2.55 / 2.43 s** (`WRAP_CACHE=off /usr/bin/time -p bash <abs path> --machine`, cwd explicit) ; 2.49 / 2.15 with cache on | **NO** |
| wrap-ledger, reso-web-app | 12.75 / 108.59 s | **6.17 / 5.35 s** | no (magnitude), direction yes |
| wrap-ledger, sevenrooms-bridge | 13.50 / 12.49 s | **6.85 / 6.16 s** | no |
| wrap-ledger, personal | 5.01 / 4.07 s | **2.17 / 2.22 s** | no |
| wrap-ledger, leaf worktree | 3.10 / 2.92 s | **1.54 s** | ~ |
| `dod_lineage_ancestors` is the hot term | ~12 re-reads ⇒ hot | **0.17 s** in claude-infrastructure (3 ancestors), **0.06 s** in reso / leaf (1 ancestor): `/usr/bin/time -p bash -c '. hooks/lib/dod-path.sh; dod_lineage_ancestors $PWD'`. Timestamped trace: dod-path.sh sites sum to **0.376 s of 5.711 s** in reso-web-app | **NO** |
| `cc-decide list --open --class C --json` | not measured | **1.08 / 1.06 / 1.08 s** standalone (191 decision files); 1.14-1.24 s inside the ledger | new |
| `cc-backlog list --all --json` | not measured | **1.74 / 1.62 s** standalone; 18,550-row / 7.7 MB `backlog.jsonl` growing 371-697 rows/day over the last 5 days (`jq -r '.ts[0:10]' \| uniq -c`) | new |
| hook_cancelled renderer / hook_error_during_execution / last_assistant_message schema | quoted | byte-exact matches in `claude.exe` (python `re.finditer`) | yes |
| `ENABLE_STOP_REVIEW` gates something | open question | **0 matches** in the 2.1.260 binary | answered: dead env var |
| IDL reconciliation rows + kills = baseline | 531 exact | now: opread 411+181=**592**, compl 530+65=**595**, boundary 521+70=**591** (±4); dispatch-assert 558, anti-def 554 are BELOW that baseline, so "dispatch-assert = invocation baseline" does not hold at this hour | mostly |
| today's Stop kills | — | **647** whole day; **≥08:22Z: opread 181, session-continue 99, boundary 70, compl 65** | new; session-continue is 15% of today's kills vs 7% over 30 d |
| 5 concurrent consumers, shared memo key | "miss simultaneously" (asserted) | reso-web-app: **8.05-8.62 s each**, ×2 Stops; claude-infrastructure: **3.67-5.01 s** | confirmed and quantified |
| `_bounded 5` bounds cc-backlog/cc-decide | assumed | `_bounded(){ command -v timeout … else "$@"; }`; `command -v timeout` fails in bash here; `ps eww` on 3 live `claude` processes: **0/3 have /opt/homebrew/bin on PATH** (where `timeout` lives) ⇒ unbounded | **NO** |

## Per-recommendation

**R1 dod-path rewrite (88%) — REFUTED as the fix.** The mechanism exists at dod-path.sh:112-142 and wrap-ledger.sh:571,582
as cited, but its measured cost is 0.17 s (both calls ≤0.35 s), and the timestamped trace puts every dod-path site at
0.38 s of 5.7 s. The 67,740-line trace count measures xtrace lines, not wall — a tight bash loop emits ~10 trace lines per
iteration at near-zero cost each; the single `cc-decide` fork emits one line and costs 1.1 s. The depth model is also
inverted: the BFS walks PREDECESSORS (`to → from`), so "root of most successions" means FEWEST ancestors (3), not most.
Byte-equality safeguard is sound; the change is harmless hygiene. Adjusted conviction as a kill-reducing change: **25%**.

**R2 hook_cancelled reader + certificate refusal (82%) — HOLDS, lowered.** Census and binary suppressions reproduce; the
certificate print is operator-readout.sh:846 / :1460 (the cited :1254 is a comment). Unmeasured: whether the
`hook_cancelled` attachment for completion-assert (killed at 5 s) is on disk before operator-readout (10 s budget) reads
the transcript in the SAME Stop — a race the report does not test; if not, the refusal arrives one Stop late. Fail
direction is correctly stated (UNKNOWN, never refuse). **65%.**

**R3 raise timeouts 10→30 / 5→20 (72%) — REFUTED on its arithmetic.** It rests on "p99 uncached ~14 s", which did not
reproduce (solo 2.2-6.9 s; 5-way contention 3.7-8.6 s). 15 s would cover every measurement here; 30 s institutionalises
a hang that `_bounded` cannot cap (no `timeout` on the hook PATH). And the term is store-growth-driven (backlog +500-700
rows/day), so any fixed raise decays. Direction (silent → slow-but-visible) is right. **50%** for a smaller raise paired
with fixing `_bounded`.

**R4 last_assistant_message (80%) — HOLDS.** Schema verified byte-exact; four cited jq scans verified at the cited lines;
only stop-failure-marker.sh and subagent-stop.sh read the field today. Report's own sizing (≈0 kills) is honest. **75%.**

**R5 goal-inert-watch bound from arm (76%) — HOLDS.** goal-state.sh:38,84 and goal-inert-watch.sh:208-215 verified; 5 kills,
p50 95 MB reproduced. Correctness-under-growth change worth 5 kills/30 d. **70%.**

**R6 opread pre-filter (55%) — REFUTED.** The anti-def analogy is confounded: anti-def is cheap because it abstains
`no-tell` on 96% of stops, not because its gate is a model to copy; operator-readout is the operator's only steps surface,
so a pre-filter that suppresses it converts a loud 24% into a silent, unmeasurable loss (cost-gate-must-be-strictly-weaker).
Once the ledger's store scans are bounded/cached, this removes nothing. **30%.**

## What the axis MISSED

1. **The real hot terms**: `cc-backlog list --blocked --json` + `--all --json` + `cc-decide list` — three forks over
   append-only stores (7.7 MB backlog, 191 decision files) reached only on the ✅/👤 rungs. This is why a CLEAN tree is
   the expensive case and why kill rate varies by cwd (reso/sevenrooms clean ⇒ 5-7 s; claude-infrastructure dirty ⇒ 2.5 s).
2. **`_bounded` is inert in hook context** — `timeout` lives in /opt/homebrew/bin, absent from the Claude process PATH
   (0/3 live processes). Every `WRAP_*_TIMEOUT_S` knob is dead; the only bound is the Stop budget that kills the whole hook.
3. **The memo's single-flight is FAILURE-1 live**: winner 2-6 s > 750 ms ladder ⇒ all five consumers compute; measured
   8.0-8.6 s each in reso-web-app. The report asserts "miss simultaneously" but never measured the multiplier.
4. **session-continue** — 99 kills after 08:22Z today (vs 65 for completion-assert); it is the mechanical-🔧 / ship-floor
   BLOCKING gate, and the report files it under 2.9%.
5. **The inverse load correlation is unexplained** and the "load is not the driver" conclusion contradicts the contention
   measurement above; the closes/min proxy likely stratifies on session TYPE (headless/subagent bursts), not on load.
6. **Reproducibility**: the appendix command `(cd $repo && bash scripts/wrap-ledger.sh --machine)` cannot have run in
   reso-web-app, sevenrooms-bridge or personal — none has `scripts/wrap-ledger.sh`. The path actually used is unstated.
7. `ENABLE_STOP_REVIEW` is not in the 2.1.260 binary at all (open question 4 closed).
