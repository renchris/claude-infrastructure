# W2-B2 — the Stop-path hot term is `cc-decide`, not `cc-backlog`: 56% of uncached wall time, removable byte-identically at 13-19x

**The number.** The hot term on the Stop path is `cc-decide list --open --class C --json` at
**1.265 s of a 2.251 s uncached `wrap-ledger.sh --machine`, 56% of wall time (63.3% by per-line
trace attribution)**. It is hot for one structural reason: `cmd_list`'s `--json` leg forks **one
`jq` per packet file** — 198 files today, 199 forks. A single-`jq`-pass replacement measures
**0.065 s median, a 19.5x speedup**, byte-identical over the live store (47,209 B, 30 rows,
`cmp` clean); the fail-tolerant variant that must ship instead measures **0.095 s, 13.3x**.
Against the 5 s Stop budget the fix returns **23.4 percentage points** (per-Stop wrap-ledger cost
2.325 s → 1.155 s, 46.5% → 23.1% of budget).

**Verdict for W3: CROSSES 90 (94) — but the target is REDIRECTED.** Both designs the row
proposed are refuted as the right target (see §4).

## 1. Population and denominator

- Code under test: `scripts/wrap-ledger.sh` at `origin/main`. **W1c rank 8 HAS landed**
  (`223369d30`, `fix(wrap-ledger): _bounded gated on PATH`) and every number here is post-rank-8.
  `BOUND_SRC=/opt/homebrew/bin/timeout` in this session, i.e. the bounded path, not the degraded fork.
- `WRAP_TRANSCRIPT` = a real 22,015,048 B transcript
  (`~/.claude-next/projects/-Users-chrisren-Development-chris-capital-group-contributions/e247265b-….jsonl`).
- cwd = the `exhaustive-drive` wave worktree. Box: 10 cores.
- Stores as measured: `~/.claude/autonomy/decisions/` = 198 packet files, 30 open class-C;
  `~/.claude/autonomy/backlog.jsonl` = 19,101 lines / 7,263,634 B, yielding 5,469,716 B of JSON.
- **Load stated at every sample** (the row's dispute is load-regime vs intrinsic cost).

**Excluded strata, named:**
- `--readout` / `--full`: human surfaces, uncached by construction, not the Stop path.
- Sessions where `SID` is unresolvable: every store read short-circuits to `SRC=none`, cost ~0.
- **Arm B is modelled, not traced end-to-end** — see §3. In this session the rung was
  `📦 Land IN FLIGHT`, which short-circuits the backlog reads; their cost is measured directly
  instead, which is cwd-independent because both read the global store.

## 2. Measurement — Arm A (rung decided early; backlog reads short-circuited)

Re-runnable, from the worktree, with `TR` set to a 2-25 MB transcript:

    WRAP_CACHE=off WRAP_TRANSCRIPT=$TR bash scripts/wrap-ledger.sh --machine     # cold
    WRAP_CACHE=on  WRAP_TRANSCRIPT=$TR bash scripts/wrap-ledger.sh --machine     # warm
    WRAP_CACHE=off WRAP_TRANSCRIPT=$TR PS4='+ ${EPOCHREALTIME} ${LINENO} ' \
        bash -x scripts/wrap-ledger.sh --machine 2>trace.txt                     # attribution

| arm | samples (s) | median | load1 |
|---|---|---|---|
| uncached (`WRAP_CACHE=off`) | 2.199 2.093 2.343 2.350 2.251 | **2.251** | 63-67 |
| cached (`WRAP_CACHE=on`) | 0.076 0.087 0.066 0.065 0.074 | **0.074** | 66 |
| uncached, load sweep | 2.892 2.922 2.430 2.443 2.056 | 2.443 | 72-78 |

Cached vs uncached byte-diff: the **only** differing field is the live land-elapsed seconds
inside `READOUT` — a clock, not a cache defect.

Per-line attribution, 3 traced uncached runs (6.519 s traced total):

| share | seconds | line | term |
|---|---|---|---|
| **63.3%** | 4.126 | `:923` | `cc-decide list --open --class C --json` (`count_blocking_decisions`) |
| 12.4% | 0.807 | `:675` | `goal_liveness` (bounded `bash -c`) |
| 2.2% | 0.145 | `:520` | `land_inflight_live` |
| 1.0% | 0.068 | `:492` | `git status --porcelain` |
| <1% each | — | `:470-502` | `git rev-parse` / `rev-list` / `cherry` |

~8% of traced time lands on comment lines — `bash -x` reports the enclosing construct's `LINENO`.
It is noise on the small terms and cannot move the 63% one.

Direct timing of the hot term alone confirms the trace: `cc-decide list --open --class C --json`
= 1.421 / 1.219 / 1.216 s (load 61), i.e. **56% of the 2.251 s total** measured independently of
`bash -x` overhead.

**The load dispute resolves as INTRINSIC.** Across load1 51-102 the uncached path spans
2.056-2.922 s — a ~40% spread, not a 6x one. A01's 14.3 s is **not reproducible in this regime**;
it needs its own explanation (a colder page cache, or a pre-rank-8 unbounded fork under a
different store size) and must not be quoted as this path's cost. The lead's 1.6-2.1 s is
confirmed and is the honest figure.

## 3. The structural finding — the row's own target does not run in most sessions

`count_blocking_decisions` (the `cc-decide` read) is called **unconditionally at `:1742`, before
the rung branch**. The three `cc-backlog`-side terms — `count_operator_steps`,
`count_filed_undriven`, `compute_close_floor` — are called at `:1784-1786` **inside the `else` of
the rung ladder**, i.e. only when no worse rung governs. In this session's `--machine` output:
`FILED_SRC=skip`, `CLOSE_FLOOR_SRC=n-a`, `DRAIN_SCOPE=0`; `:755` documents `skip` as *"not
computed (a worse rung already governs)"*.

So the reads are **already lazily gated**, and the one term no rung can skip is `cc-decide`.

**Arm B (fall-through rung) costed directly**, since both reads hit the global store:

| term | samples (s) | median |
|---|---|---|
| `cc-backlog list --blocked --json` | 0.067 0.063 0.060 | 0.063 |
| `cc-backlog list --all --json` (5.5 MB out) | 0.071 0.061 0.061 | 0.061 |
| 3 `jq` passes over that 5.5 MB | 0.211 0.194 0.195 | 0.195 |
| **Arm B addition** | | **≈0.35 s** |

Arm B total ≈ **2.60 s**, of which `cc-decide` is still ~49% and the whole `cc-backlog` side ~13%.
`cc-backlog` is cheap **because it is already one `jq` pass over one file** — the exact shape
`cc-decide` lacks.

## 4. Prototypes — both proposed designs refuted, a third one measured

**(a) A fold snapshot for `cc-backlog list`, keyed on `backlog.jsonl` (size, mtime) — REFUTED as
the target.** It aims at 0.061 s (2.7% of Arm A, 2.3% of Arm B). Even a perfect hit rate cannot
return more than ~0.26 s including the jq passes, and it buys that by adding a key that a
`cmd_compact` rewrite (`bin/cc-backlog` `mv` under `_bl_compact_lock`) can defeat: compaction
shrinks the file, so (size, mtime) does move — but the file's own header at `:220-222` already
records the governing law from a prior attempt, *"a cache may never make the uncached path worse
than uncached, and that is a property of the ARRIVAL PATTERN, not of the hit rate."* Not worth a
new invalidation surface for 2.7%.

**(b) A single `jq` pass replacing the three store reads — REFUTED as stated.** The three reads
are in two different binaries over two different stores and, per §3, two of the three do not run
in the same sessions as the third. There is no single pass to fold them into.

**(c) The measured fix — collapse `cc-decide cmd_list --json`'s per-file fork loop into one `jq`
invocation** (`bin/cc-decide:388-398`). `jq` accepts many file arguments; the prototype sources
the real binary's own `CELL` / `SFOLD` / `LIST_SELECT` prelude rather than re-implementing it.

| arm | samples (s) | median | vs real |
|---|---|---|---|
| real `cc-decide` (interleaved control) | 1.330 1.276 1.144 1.214 1.265 | 1.265 | — |
| naive single pass | 0.071 0.074 0.059 0.058 0.065 | 0.065 | **19.5x** |
| tolerant single pass (ship this) | 0.095 0.119 0.084 | 0.095 | **13.3x** |

Byte-identical over the live store: `cmp` clean, 47,209 B, 30 rows, both variants.

🚨 **The naive pass is WRONG and the fixture proves it.** `jq` stops at the **first** unparseable
input, so one malformed packet silently drops **every packet after it**. Fixture: 4 packets, the
3rd truncated, glob order `a1 a2 a3 a4` —

    real cc-decide:  pkt1, pkt2, pkt4     (drops only the bad one, silently)
    naive one-pass:  pkt1, pkt2           (drops pkt3 AND pkt4, silently)

That is a silent under-count of the open class-C packets that decide the `⛔` rung
(MEMORY.md *parse-failures-are-verdicts-not-noise*, *suppressed-stderr-turns-a-failed-command-into-a-zero*).
The **tolerant** variant runs the one-pass, and **on a non-zero `jq` exit treats it as INCOMPLETE
rather than as zero rows** — falling back to the per-file loop and reporting the parse-failure
count on stderr. On the same fixture it returns `pkt1, pkt2, pkt4` **and prints
`cc-decide: 1 unparseable packet file(s) — served the per-file fallback`**, which is strictly
better than today's binary: today that packet vanishes with no tell at all.

Prototypes live in this session's scratchpad (`b2-decide-proto.sh`, `b2-decide-proto2.sh`,
`b2-attrib.py`, `b2-findings.md`) and are deliberately **not** committed, per the brief.

## 5. What a wrong reading would look like (the fail direction)

- **Reading Arm A as the whole path.** A session whose rung is decided early never runs the
  backlog reads, so a trace taken there reports `cc-backlog` at 0% — an absence of measurement,
  not an absence of cost. §3 costs it directly for exactly this reason.
- **Believing `jq length` over an unchecked file.** An early sample here printed `rows=` empty and
  looked like a failed read; `rc=0` and 5,469,716 valid bytes said otherwise. The instrument was
  the bug (nested quoting), not the data — check `rc` and the byte count before indicting a store.
- **Shipping the naive one-pass because the live store is clean today.** It is byte-identical
  *until* one packet is malformed, and then it fails silently and under-counts the rung that
  blocks a close. The correctness arm must be a fixture with a bad file in the MIDDLE of glob
  order; a bad file LAST would pass and prove nothing.
- **Quoting 14.3 s or 0.074 s as "the" cost.** 0.074 s is the warm memo serving a second caller
  within one Stop event; the transcript's cksum changes every turn, so **every Stop pays the cold
  path once**. Two Stop-path consumers invoke it (`hooks/completion-assert.sh:260`,
  `hooks/anti-deference-nudge.sh:306`), so per-Stop cost is 2.251 s cold + 0.074 s warm =
  **2.325 s today (46.5% of budget)** and **1.155 s after the fix (23.1%)**. The key is built from
  the transcript's `(mtime, size)` (`:374` feeds `_wl_stat_ms "$WL_TRANSCRIPT"` into `WL_KEY`), and
  the transcript grows every turn — so the memo is COLD on every Stop by construction and warm only
  for the second consumer within one Stop event.
