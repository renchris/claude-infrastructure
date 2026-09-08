# A01 — Stop-hook timeout decay — SKEPTIC verdicts

Wave: exhaustive-drive, 2026-09-08. Read-only. Role: refute the axis report at
`A01-stop-hook-timeout-decay.md`. Every number below says whether I ran it (measured) or took it
(inferred / lead-measured). Load average during my measurements: 135–255 on 10 cores (`sysctl -n
vm.loadavg`), i.e. 2–10× the load the axis measured under — so I read RATIOS, not absolutes, and
compared back-to-back runs in the same cwd.

---

## Answer first

**The census holds; the size-refutation holds; the root cause is wrong.** Stop hooks are being killed
at the scale the axis measured (my independent recount of one root: 913 Stop timeouts vs the axis's
902 for that root — same population, a few files newer). But the hot term is not
`dod_lineage_ancestors`. That BFS costs **0.17 s** inside a 2.5 s ledger in claude-infrastructure and
**0.07 s** inside an 8.6 s ledger in reso-web-app (timestamped `bash -x`, measured). The 5,352 trace
lines were a COUNT read as wall time — the exact defect the memory index names (`count is not
content`). claude-infrastructure has **two** ancestors in `lineage.tsv` (3 output lines), not
"maximum depth": the ancestor walk goes from a cwd to its PREDECESSORS, so the root of successions is
the shallow end, and `lineage.tsv` is byte-identical across cwds, so it cannot produce a per-cwd spread
at all.

**What the wall time actually is**, measured: three `_bounded 5` reads of the operator stores —
`cc-backlog list --blocked --json` (2.83 s), `cc-backlog list --all --json` (3.19 s), `cc-decide list
--open --class C --json` (1.44 s) — **7.5 of 8.6 s** in reso-web-app. `cc-backlog` is a 6,725-line
bash script with 158 `jq` invocations that folds an 18,520-row append-only event log (7.6 MB) on every
read; raw `jq -c .` over that file is 0.27 s user, `cc-backlog list --all --json` is 1.63 s user, so
the fold, not I/O, is the cost, and it grows with the store (~400 rows/day).

**And those reads run only on the ✅-eligible path** (`scripts/wrap-ledger.sh:1748`, inside the
`else` of the 🔧/📦 branch — on a dirty or unlanded tree every store read reports `SRC=skip`). So the
per-repo kill spread the axis attributed to lineage depth is **porcelain state**:

| cwd | porcelain | RUNG | wrap-ledger --machine, uncached (measured) |
|---|---:|---|---:|
| .worktrees/exhaustive-drive | 12 | 🔧, all SRC=skip | 1.74 s |
| claude-infrastructure | 22 | 🔧 | 1.98 / 2.37 / 2.52 s |
| personal | 1 | 🔧 | 2.84 / 2.89 s |
| reso-web-app | 0 | ✅ | 8.60 / 8.89 / 9.85 s |
| sevenrooms-bridge | 0 | ✅, all SRC computed | 7.62 / 9.19 / 10.78 s |

The axis reported `git status --porcelain` = 0 for claude-infrastructure when it measured 14.38 s
there; it is 22 now (the untracked files are a month old — `accounts.json.pre-router.20260811…`,
`docs/plans/backlog-consolidation-2026-08-09/`), and at 22 the same script in the same cwd costs
2.0–2.5 s at 2× the load. Whatever the axis's tree looked like, "identical git tree, identical
lineage, therefore depth" does not survive: the variable that differed was the rung path.

**The certificate path is the slow path.** The close that renders `✅ SAFE TO CLOSE` is the one that
pays the store reads, so it is the one most likely to be killed. This inverts the axis's framing
("the certificate renders anyway under a killed gate"): on today's data, all 20 sessions where
operator-readout never logged a single row (69 kills, 100% loss) sit in CLEAN trees —
sevenrooms-bridge (porcelain 0; 15 kills, 0 rows), `.worktrees/wt-pool-2` (0 / ahead 0),
`wt-f4863408f038` (0 / 0), `wt-193ae8ddce72` (0 / ahead 1); the rest are worktrees since removed.
The axis noted the bimodality (23 fully covered, 20 fully missing) and left it unexplained; this is
the explanation.

**The memo is inert at the one event it was built for.** Five concurrent callers in reso-web-app with
the same `WRAP_TRANSCRIPT` (measured): **all five computed**, 13.43–14.41 s each, total wall 14.58 s,
against 8.6 s for one caller alone — contention inflates each ~1.6×. The single-flight wait ladder is
50+100+200+400 = 750 ms (`wrap-ledger.sh:418-428`), calibrated when the header says the uncached
compute was 0.48 s; the compute is now 2–10 s, so every loser expires the ladder and computes.
`completion-assert` passes `--session $SID` and therefore never shares a key with the other four
anyway (`:262-265`). Second-round warm calls: 0.06–0.07 s — the cache works, it just never gets the
chance at a Stop.

---

## Numbers rechecked

| name | axis claimed | I got (command) | holds |
|---|---|---|---|
| Stop-hook timeouts, 30 d | 4,839 across four roots (902 in `~/.claude`) | 913 in `~/.claude/projects` alone, streaming Python over `*.jsonl` mtime ≤30 d matching `attachment.type==hook_cancelled && hookEvent==Stop && timedOut==true` | yes |
| per-hook ranking | opread 2,873 · compl 1,381 · s-c 342 · b-h 164 | same order in one root: 552 · 239 · 68 · 33 | yes |
| wrap-ledger claude-infrastructure uncached | 14.38 / 14.27 s | 1.98 / 2.37 / 2.52 s at load 255, porcelain 22 (`time bash scripts/wrap-ledger.sh --machine`) | **no** — reproduces only on a clean tree |
| wrap-ledger reso-web-app / sevenrooms-bridge | 12.75 / 13.50 s | 8.60–9.85 s / 7.62–10.78 s single; 13.4–14.4 s under 5-way contention | yes, within load variance |
| wrap-ledger leaf worktree | 2.92–3.10 s | 1.74 s (exhaustive-drive, porcelain 12) | yes |
| `git status --porcelain` | 0.02 s | 0.020 s (gap in timestamped trace) | yes |
| `dod_lineage_ancestors` 5,352 read-r iterations | "the hot term" | 0.158 / 0.218 / 0.279 s standalone ×3; 0.173 s summed over all BFS-loop lines in the claude-infra trace; 0.074 s in the reso trace; output = 3 lines | count yes, **attribution no** |
| trace lines / git calls | 67,740 / 19 | 67,583 lines; largest gap `_bounded 5 …cc-decide list --open --class C --json` 1.236 s | yes on the count; the count is not the cost |
| `anti-deference-nudge.sh:288` gate | `if ship_hold or has_done` | line 288 verbatim | yes |
| binary: `case"hook_cancelled":{if(w.hookEvent!=="UserPromptSubmit"\|\|!w.timedOut){return null}` | quoted | found verbatim, 1 hit, mmap regex over claude.exe | yes |
| binary: `case"hook_error_during_execution":{if(w.hookEvent==="Stop"\|\|w.hookEvent==="SubagentStop"){return null}` | quoted | found verbatim, 1 hit | yes |
| binary: `last_assistant_message:s().optional().describe("Text content of the last assistant message before stopping. Avoids the need to read and parse the transcript file.")` | quoted | found verbatim, 5 hits (Stop schema is the one followed by `background_tasks`) | yes (schema); runtime presence on Stop is inferred — no raw Stop payload capture exists on this box |
| goal-inert-watch kills 5, p50 90.8 MB | as stated | 5 rows: 90.8 / 101.0 / 114.1 MB all on 2026-08-17 (one session), plus 7.1 MB (durationMs 10,012) and 9.0 MB (8,596) — the last two overran a 5 s budget at small size | yes, but n=3 for the size story |
| certificate site `operator-readout.sh:1254` | cited | `SAFE TO CLOSE` is at :846 (`state="✅ SAFE TO CLOSE — nothing of mine is open"`); :1254 is a stale cite carried from CLAUDE.md | **no** |
| kills are a "pervasive per-close tax, not a load storm" | 30 d aggregate, 24.2% | daily opread kills ÷ per-close timestamps (`closes-ts.txt`): 08-11..08-15 **0–6%**; 08-16..19 15–21%; 08-20..28 24–55%; 09-02..04 **74–88%**; 09-06..08 30–44% | **partly** — not size, not bursty, but RISING, not flat |
| durationMs ≈ timeoutMs | implied | 2,775 of 2,873 opread kills within 200 ms of budget; 98 overran by more (SIGKILL lag under load) | yes |
| 469 = 469 IDL reconciliation | lead-measured | not re-run | accepted |

Daily trend detail (measured, per-close timestamps from the axis's `closes-ts.txt`, kills from
`cancels.tsv`):

```
day    closes  opread%  compl%      day    closes  opread%  compl%
08-11    477     5.9     1.5        08-25    601    35.6    15.5
08-12    298     1.3     3.0        08-26    554    54.5    24.4
08-13    193     3.6     6.2        08-27    362    22.4    41.4
08-14    184     0.5     0.0        08-28    255    46.3    25.5
08-15     97     0.0     0.0        09-02    136    87.5    23.5
08-16    445    18.4     5.8        09-03    100    74.0    35.0
08-17    341    21.4     9.4        09-04    241    88.4    39.0
08-20    202    38.6     8.9        09-06    507    43.6    14.4
08-21    606    23.9    19.3        09-07    242    29.8    19.4
08-23    781    31.5    16.3        09-08    880    30.2    10.1
```

Over the same window `backlog.jsonl` went from 5,982 rows (08-08) to 18,515 (09-08) — the store
`cc-backlog` folds on every read tripled. The second full-store read (`list --all --json`,
FILED_MINE) entered the Stop path on 2026-09-04 (`96db63710`); 👤 (`list --blocked`) on 08-01
(`e880674fc`); ⛔ (`cc-decide`) on 08-07 (`b08601974`). A note on my first pass: `all.tsv`'s second
column is the FILE mtime, not the close time — bucketing closes by it produced daily rates above 100%
(09-02: 119 kills / 91 "closes"); the table above uses the per-close timestamps and is the one to
trust.

Co-occurrence (measured): of 1,381 completion-assert kills, **739 (53.5%)** have an operator-readout
kill in the same file within ±6 s. So the "certificate rendered underneath a killed gate" exposure is
~640 Stops in 30 d, not 1,381 — in the other half both are dead and nothing renders.

Attachment ordering (measured, 60 sampled completion-assert kills): the `hook_cancelled` record is
written AFTER the assistant close, interleaved with the other hooks' `hook_success` /
`hook_blocking_error` / `hook_system_message` attachments, before the next `system`/`user` record.
A hook running at Stop N is racing the writer if it tries to read a sibling's kill at Stop N.

---

## Verdicts, per recommendation (axis order)

### R1 — rewrite `dod_lineage_ancestors` to read `lineage.tsv` once (axis 88%)

**Refuted as a cure for the kills.** Mechanism exists at `hooks/lib/dod-path.sh:112-142` exactly as
described, and it does re-read the file per BFS level. But measured cost is 0.16–0.28 s standalone
and 0.07–0.17 s inside the ledger; two calls ≈ 0.3–0.5 s of a 2–10 s ledger. The "root = max depth"
claim is inverted (claude-infrastructure: 2 ancestors), and the file is identical across cwds so it
cannot be the per-cwd variable. Fail direction the axis stated (a different ancestor set silently
changes `Scope (frozen)`) is correct and is the only reason not to do it casually. Rechecked:
`source hooks/lib/dod-path.sh; time (dod_lineage_ancestors "$PWD" | wc -l)` → 3 lines, 0.158 s.
**Adjusted conviction it is the right change for this axis: 15%** (harmless micro-optimisation,
~0.4 s; do it only if the pure-function byte-equality diff is free).

### R2 — reader for `hook_cancelled`, wired so the certificate refuses on a killed completion-assert (axis 82%)

**Partly refuted.** The records exist and nothing reads them — verified. Three problems with the
wiring as worded: (a) same-Stop refusal is a race — the kill record lands after the hooks finish;
the feasible shape is one Stop late ("last close's gate was killed") or a standalone reader;
(b) 53.5% of the time operator-readout is dead too, so there is no certificate to refuse; (c) the
cite `operator-readout.sh:1254` is wrong (`:846`). House-rule risk: on a clean tree the gate is killed
at ~41% of the closes that reach the ledger (axis's conditional figure, plausible given my clean-path
timings), so a certificate that reads UNKNOWN there is an alarm that fires on the busiest legitimate
path — `alarm-polarity-and-attention-budget.md`: it would carry few bits and train the operator to
ignore it. Fail direction: errs LOUD on the ✅ path, which is the path the operator most needs to
trust. **Adjusted: 45%** — build the reader (it is the only local instrument for this loss) and fold
it into `wrap-ledger` as a counted term, but do not make it the certificate's veto until the cost
fix below has brought the clean-path kill rate under a few percent.

### R3 — raise operator-readout 10→30 s and completion-assert 5→20 s, migration-class c10 (axis 72%)

**Partly holds; the arithmetic changes.** The budgets it must cover are 8.6–10.8 s for a lone clean
close and 13.4–14.4 s under the 5-way self-contention the memo fails to prevent — not the axis's 14 s
from lineage depth. c10 convention verified (`migrations/README.md:34-68`). Two objections the axis
did not weigh: the cost is RISING with the store (0–6% in mid-August, 74–88% in early September), so
a fixed raise decays; and raising budgets without fixing the single-flight leaves 5 concurrent
computes per Stop, so every clean close becomes a 14 s wait for the operator. Fail direction: LOUD
(visible hang), correctly stated. **Adjusted: 55%**, and only as a same-commit companion to the
store/memo fix — never with the BFS fix, which buys nothing.

### R4 — read `.last_assistant_message` from the Stop payload in the four scanning hooks (axis 80%)

**Holds** on mechanism (schema verbatim in 2.1.260; `final-response-shaping-2026-08-08.md:184`
asserts the payload carries it), with one honesty note the axis half-made: the "measured-present"
citations are StopFailure (`stop-failure-marker.sh:5`) and SubagentStop (`subagent-stop.sh:93`), not
Stop — no raw Stop payload is captured anywhere on this box, so presence on Stop is inferred from
the schema. Axis correctly says it earns ~0 kills. Fail direction (fallback on ABSENCE, never on
EMPTY) correctly stated. **Adjusted: 70%** — a correctness/simplicity change, not a kill fix.

### R5 — bound goal-inert-watch's scan from the last ARM record (axis 76%)

**Holds on mechanism** (`goal-state.sh:38` `grep -a goal_status | jq --slurp`; `goal-inert-watch.sh:208-215`
`tail -n +N | jq`, verified) and on fail direction (the axis's reading of `goal_liveness`'s
since-last-arm semantics matches the file's own header). Evidence is thin: 3 of the 5 kills are one
session on 2026-08-17 at 90–114 MB; the other 2 are at 7–9 MB with 8.6–10 s durations against a 5 s
budget — not size. **Adjusted: 60%** — correct under growth, worth ~3 kills; do it when touching the
file.

### R6 — a cheap pre-filter in front of operator-readout's render (axis 55%)

**Refuted.** The ledger already has the pre-filter: on 🔧/📦 every store read is `SRC=skip`
(`wrap-ledger.sh:1748` and the `else` it sits in) and the ledger costs 1.7–2.9 s. The expensive path
is the ✅-eligible one, where the stores ARE the predicate — no cheap lexical test can decide 👤/⛔/
FILED_MINE without reading them, so any pre-filter here is either not strictly weaker (shadows the
gate — `cost-gate-must-be-strictly-weaker.md`) or does nothing. **Adjusted: 20%.**

---

## What the axis missed that its question required

1. **The hot term is the operator-store reads, not the lineage BFS** — `cc-backlog list --blocked/--all
   --json` (2.8 + 3.2 s) and `cc-decide list --open --class C --json` (1.2–1.4 s); `cc-backlog`
   folds an 18.5k-row event log in bash+jq on every call (1.4–1.6 s user vs 0.27 s to parse the file).
   The remedy the axis did not reach: one `jq` pass over `backlog.jsonl` serving both queries, or a
   `cc-backlog` fold snapshot keyed on the log's (size, mtime) — S/M, files `bin/cc-backlog`,
   `scripts/wrap-ledger.sh:726,813`. Fail direction: a snapshot keyed on the log's stat serves stale
   state only if something rewrites the log in place (it is append-only) — and the axis's own
   FAILURE 2 note says directory mtimes lie, so key on the FILE's size+mtime, never the directory's.
2. **The clean-tree inversion.** Store reads run only on the ✅-eligible path, so the certificate
   close is the slow close. The 110× per-repo spread is porcelain state; all 20 never-logged
   sessions today are clean trees. This also explains the bimodality the axis left open.
3. **The single-flight memo never fires at a Stop.** 750 ms ladder vs 2–10 s compute ⇒ 5 of 5
   callers compute (measured), inflating each ~1.6×. The header's 0.48 s / 3.7 s-p50 calibration is
   10–20× stale — `bound-must-fit-the-band-not-the-bench.md`. Remedy: a wait bounded by the winner's
   REAL cost (or a lock the losers block on with a ceiling under the hook budget), and drop
   completion-assert's `--session` from the key or give it its own compute deliberately. Fail
   direction: a longer wait makes a slow winner slow everyone — but they all compute today anyway.
4. **The tax is rising, not flat.** Daily kill rate 0–6% → 74–88% over 3 weeks while the store
   tripled and two store reads joined the Stop path (08-07 ⛔, 09-04 FILED_MINE). A 30-day aggregate
   hid the slope; any fixed budget raise decays against it.
5. **Co-occurrence.** 53.5% of completion-assert kills also kill operator-readout; the "certificate
   under a killed gate" exposure is ~640/30 d, not 1,381.
6. **Which kills matter for the operator's goal.** operator-readout emits `systemMessage` only — its
   24.2% loss costs the operator's readout, never model behaviour. The kills that bear on "keep
   working until a hard blocker" are completion-assert (block on false-done, 11.6% overall / ~41%
   of ledger-reaching closes) and session-continue (block on 🔧/ship-floor, 2.9%). The axis weighted
   by count, not by consequence.
7. **Same-Stop reads of `hook_cancelled` are a race** — the record is written with the other hook
   attachments after the hooks complete.
8. **Stale cite** — the certificate is `operator-readout.sh:846`, not `:1254`.
9. **Timing harness confound** — the axis's 12-rep "0 of 96 runs exceeded" used one fixed 2.0 MB
   transcript, so reps 2–12 hit the memo cache for every wrap-ledger consumer; it measures the
   cached path, not the Stop path.

## Reproduction

Artifacts under `…/scratchpad/a01skep/`: `trace.txt` (claude-infrastructure, `PS4='+T $EPOCHREALTIME'
bash -x scripts/wrap-ledger.sh --machine`), `trace-reso.txt` (reso-web-app), gap ranking = sort
consecutive-timestamp deltas; concurrency test = five backgrounded `wrap-ledger.sh --machine` with one
static `WRAP_TRANSCRIPT` in reso-web-app, wall per caller via `python3 -c 'import time…'`; daily rates
from the axis's `a01/closes-ts.txt` and `a01/cancels.tsv`.
