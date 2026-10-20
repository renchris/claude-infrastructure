# B4: make `claude-accounts --place` cheap. Implementation design

**Verdict: BUILD. Conviction 85%.** An agent can implement, test and land every part. The
reconciler half goes live at the daemon's next restart, which must not be forced in the middle of a
cohort (A6). No operator ruling is needed.

**Labels.** *Measured* (M) means read from a named command or file, run by me on 2026-10-20
between 17:37Z and 18:35Z, with load1 printed beside the reading. *Estimated* (E) names its method.
*Hypothesis* (H) is not verified.

**Code citations.** They are to this worktree at `28b25a119`; `bin/claude-accounts` is identical
there and on `main` at `6fdf87eca` (M: `git diff --stat 28b25a119 HEAD` in the shared checkout
lists only three test files). Everything I ran was read-only against live state. Prototypes,
snapshots and harnesses live only under `/tmp/b4/`. No repo file was edited.

---

## 0. Summary

`--place` costs seconds, and up to 120 s in band 20. The cause is two corpus scans, not load as
such, and both grow without limit:

1. **The store check `holds()`** (`bin/claude-accounts:6637-6638`, called at `:6658`). It globs
   `<store>/projects/*/<sid>.jsonl`, which means one `lstat` in each of the 18,197-18,406 project
   dirs per store (M: `ls -1 <cfg>/projects | wc -l`). It runs for every mover × every non-source
   account with room, before facts, floors and scoring.
2. **The utilization read in `apply_burn`** (`:4856` → `_util_tail_read` `:4657-4748`). `--place`
   needs at most 48 h of it. It asks for 336 h. Because of a defect in the read's stop rule, it
   actually parses the **whole 19.5 MB file twice on every call**, for any span from 2 h to 336 h
   (§1.4).

The design keeps `--place` as the only scorer (`plan.py:3-5`), keeps every answer byte-identical,
and adds no cache, no second scorer and no extra subprocess:

| # | Where | Change |
|---|---|---|
| **C1** | `claude-accounts` `cmd_place` | Trust a per-mover `holds: {acct: bool}` map when one is supplied. Glob only for an account the map omits |
| **R1** | `lr_recon` `_plan` | Compute that map from the daemon's kept `transcript.ProjectsIndex`, which already gives the glob's answer at near-zero cost |
| **C2** | `claude-accounts` `cmd_place` | Read 49 h of the utilization series, not 336 h. The three burn fields `--place` reads are bit-identical |
| **C3** | `claude-accounts` `_util_tail_read` | Stop once the read has reached back past the cutoff. This is the documented contract (`:4718-4719`), which the code does not implement |

**Effect, measured at priority 31 on the live corpus with 9 movers:**

| | Original | Prototype |
|---|---|---|
| Wall | 4.75-11.7 s (load1 156-185) | 0.15-0.56 s (load1 167-199) |
| CPU | 4.3-4.9 CPU-s, 63-66% of it kernel time | 0.15 CPU-s |
| Wall in band 20, 3 movers | 54-65 s (load1 206-247) | 1.1-2.5 s (load1 266) |

Across 40 randomized cases on frozen inputs the answers were identical, with 78 real "store holds
the sid" entries exercised (§7).

---

## 1. Evidence: the code path and what scales

### 1.1 The code path

| Step | file:line | Cost driver |
|---|---|---|
| Interpreter start, compile of the 11.6k-line script (a script's `__main__` is never byte-cached) | shebang; `main` `:10947` | Fixed (~0.1-0.4 s foreground, axis 06 §1) |
| `load_cfg(need_claude_bin=False)` | `:11051`, `:395-416` | Fixed |
| `--place` dispatched before the `get_data` anchor | `:11190-11191` | — |
| `_place_load_inputs` (movers JSONL, kwork, facts dir) | `:6472-6501` | n movers |
| `get_data(max_wait=0, max_age=600)`: cache-only, never sweeps | `:6532`, `:8237-8259` | 4.6 KB cache (M: `ls -la /tmp/claude-accounts-cache.json`) |
| `apply_assignments`: ledger read 4× | `:6540`, `:4527-4557` | 207 lines (M: `wc -l account-assignments.jsonl`) |
| **`apply_burn` → `_util_tail(hours=336)`** | `:6541`, `:4856`, `:4657-4748` | **whole utilization log ×2 (§1.4)** |
| `_place_read_facts` | `:6549`, `:6415-6431` | A few files |
| Capacity loop (an account-level fact gives cap 0) | `:6568-6584` | 4 accounts |
| `_live_assignments` for own phantoms | `:6590-6594` | Ledger |
| Per mover × per account: room check, then **`holds()`**, then model fact, src fact, floors, score | `:6643-6691`, `holds` `:6637-6638` | **movers × accounts with room × ~18.3k lstat** |

Two notes on ordering. `holds()` runs before the model-fact, floors and score checks, and right
after the room check (`:6655-6658`). It is skipped only for the source account and for an account
with no room; an account-level fact zeroes the cap at `:6575-6577`. So the skeptic's "65% is an
upper bound because capacity and fact checks run first" (axis 06 F3 caveat 1) holds only for
account-level facts. A "stay" answer still globs every other account with room.

### 1.2 Profile at priority ~31, at today's load (M)

`python3 -m cProfile` of the exact reconciler argv (`plan.py:308-327`): 3 synthetic movers,
kwork 5 on every account, an empty facts dir. All writes went to `/tmp`
(`CLAUDE_ACCOUNTS_LOG=/tmp/b4/ca.log`, `PYTHONDONTWRITEBYTECODE=1`). load1 278 at the start.
`ps -o pri -p $$` gave 30.

| Function | Cumulative | Share | Calls |
|---|---|---|---|
| `cmd_place` | 15.74 s | 100% | — |
| `holds` → `glob.glob` | 10.08 s | 64% | 9 globs, **164,800 `posix.lstat` (6.34 s)** |
| `apply_burn` → `_util_tail_read` → `_parse` | 5.59 s (4.71 s in the read) | 35% | **9 slices, 144,631 `json.loads`** |
| Everything else | ~0.1 s | <1% | — |

The same shape as axis 06's foreground profile: 65% / 29%.

### 1.3 What scales, and with what

| Term | Scales with | Load-sensitive? |
|---|---|---|
| `holds()` | movers × (accounts with room − source) × project dirs per store. The dirs only grow, one per worktree path ever opened: 18,197 / 18,327 / 18,403 / 18,406 today (M) | **Yes, through the kernel, not just the band.** The lstat cost was 38 µs at load ~250 (my profile) against 10 µs in axis 06's foreground profile. Under concurrent directory walkers, one glob took **9.7 s** (M: 8 globs in 77.2 s while two other walkers ran) against **0.23 s** alone (40 globs in 9.34 s at load1 268). Of the original's CPU, 2.7-3.2 s of 4.3-4.9 s is `sys` (M: `/usr/bin/time -p`) |
| `_util_tail_read` | **Total retained history, not the requested span** (§1.4). Today 19,480,240 B / 56,630 rows / 1,715.9 h (M) | CPU-bound; the band multiplies it |
| Interpreter start and compile | Script size | The band multiplies it (axis 06 §1: 0.4 s foreground, 18 s in band 20) |
| Everything else | n movers × 4 accounts, in memory | Negligible |

Nothing in `--place` reads the load average.

**Production history.** Measured: 244 `place` events in `recon/events.jsonl{,.1}`, 2026-10-13 →
10-20, all from the band-20 daemon. 17 were rc 124. Answered medians by load1 band:

| load1 | 0-49 | 50-99 | 100-149 | 150-199 | 200-249 | 250-299 | 300-349 |
|---|---|---|---|---|---|---|---|
| Answered median | 2.8 s | 4.0 s | 17.6 s | 17.9 s | 24.8 s | 51.4 s | 74.3 s |

**There is no priority-31 production sample.** No `place` event has been written since the band
reload at 07:23Z (M: the last `place` row is 05:25:15Z; the last event of any kind is
`not-needed` at 1792497667, 12:01Z). So A1's effect on `--place` in production is unmeasured. My
same-moment CLI runs stand in for it (§7).

### 1.4 A defect found on the way: `_util_tail_read` parses the whole file twice on every call

**The contract** (`:4718-4719`): "Covered when we either reached back past the cutoff or read the
whole file."

**The code's test** (`:4722`): `min(r["_t"] for r in rows) <= cutoff + 60`. But `_parse` has
already discarded every row older than the cutoff (`:4695-4696`). So the test passes only if some
kept row lands within 60 s **after** the cutoff.

The log is written in bursts: all four accounts per sweep share one stamp. The inter-row gap is
p50 0 s, p90 399 s, max 33,208 s (M, `/tmp/b4/utiltail.py`). So the 60 s window is usually empty,
and the loop doubles 128 KiB → 32 MiB until it has read the whole file. It also re-parses every
earlier slice on the way, roughly twice the file in total.

Replay of the loop on a frozen copy (M, `/tmp/b4/utiltail.py`; 0 of 56,630 rows out of time order):

| Span requested | Today: slices / `json.loads` | Stop at "crossed the cutoff": slices / `json.loads` | Rows kept (identical) |
|---|---|---|---|
| 2 h | 9 / 143,792 | 1 / 302 | 60 |
| 6 h | 9 / 143,792 | 1 / 302 | 180 |
| 48 h | 9 / 143,792 | 4 / 4,448 | 1,429 |
| 49 h | 9 / 143,792 | 4 / 4,448 | 1,461 |
| 72 h | 9 / 143,792 | 4 / 4,448 | 2,241 |
| 336 h | 9 / 143,792 | 7 / 39,916 | 11,449 |

**Consequences beyond `--place`.** `apply_burn` is called on every `--rank` / `--route` / `--json` /
readout (`:11289`), on every board render (`:8001`, `:8020`) and in `fleet_pace_line` (`:5803`).
So the dispatcher's `--rank general`, which overran its 20 s bound in wave 5, `recycle_repick`'s
`--rank` (D1) and G2's ranking all pay the whole-file parse.

**It gets worse after rotation.** The log rotates at 25 MiB into `<f>.<stamp>.gz`, keeping 8
(`scripts/rotate-autonomy-logs.sh:75`, `:450`; `config/store-bounds.manifest:47`). After a
rotation the live file is short. The sibling walk at `:4727-4744` breaks on the same broken test,
so it decompresses and parses **every** retained sibling, on every call.

- E: the first rotation lands in about 24 days, ~2026-11-13 (linear: 34.1 rows/h × 344 B/row ≈
  281 KB/day against 6,734,160 B of headroom).
- E: from then on the per-call cost grows with each rotation, toward 8 siblings of ~76k rows each.
- The RP-8 test comment (`tests/claude-accounts-util-tail.bats:87`) estimated 2026-12-11 at
  237 KiB/day; the rate has risen since.

### 1.5 How often the store check binds

Measured with one read-only walk of all 4 stores (`/tmp/b4/xstore.py`: 73,335 directory reads in
5.9 s):

- 7,368 sids have a live top-level transcript.
- **24 are live in 2 or more stores, and in 0 of those 24 are the copies under different slugs.**
- 0 sids have two copies under different slugs inside one store.
- 3 of the 138 reconciler session records are live in 2 or more stores right now.
- No `store-holds-sid` verdict appears in any reconciler state (M: `grep -c` on both event logs
  gives 0, and no match in `plans/`, `sessions/` or `cohorts/`). The reason is recorded only when
  a mover ends unplaced.

What the check protects:

- `lr-transplant` refuses on arrival only for the **same** slug as the source transcript
  (`lr-transplant.sh:877-885`: `SLUG=$(basename "$SRC_DIR")`, `DST=$TO/projects/$SLUG/$SID.jsonl`,
  `REFUSED — $DST already exists`).
- A copy under a **different** slug is not refused at transplant time. It leaves the target with
  two copies, and the **next** hop off that target is refused "multiple copies of $SID …
  disambiguate manually" (`:869-875`).
- The 2026-09-19 case behind the predicate (`lr-fleet.sh:662-669`) is `07e30aeb`. It is still live
  in two stores today (my red control in §7 uses it).

---

## 2. Design

### C1. `--place` trusts a caller-supplied holds map (`bin/claude-accounts`)

**`cmd_place`, `holds` (`:6637-6638`) and its call (`:6658`)**. This is the prototype's exact diff
(`/tmp/b4/proto2.diff`):

```diff
-    def holds(a: str, sid: str) -> bool:
-        return bool(glob.glob(os.path.join(dirs[a], "projects", "*", glob.escape(sid) + ".jsonl")))
+    trust_holds = _term_on("CC_PLACE_HOLDS_MAP")
+
+    def holds(a: str, m: dict) -> bool:
+        known = m.get("holds") if trust_holds else None
+        if isinstance(known, dict) and isinstance(known.get(a), bool):
+            return known[a]
+        return bool(glob.glob(os.path.join(dirs[a], "projects", "*",
+                                           glob.escape(m["sid"]) + ".jsonl")))
 ...
-            elif a != src and holds(a, sid):
+            elif a != src and holds(a, m):
```

**`cmd_place` docstring, INPUTS (`:6508-6515`).** Add:

> `holds?` (`{acct: bool}`): the caller's own answer to "does that account's store hold a live
> `<sid>.jsonl`", from an index that gives `projects/*/<sid>.jsonl`'s answer. An account the map
> omits, or gives a non-bool for, is globbed as before. `CC_PLACE_HOLDS_MAP=off` ignores every map.

**`_place_load_inputs` (`:6487-6492`)** needs no change: it keeps unknown keys
(`dict(m, w=w)`), so a malformed `holds` simply falls through to the glob. That direction is
exact and slow, never wrong.

### C2. `--place` reads 49 h of the utilization series, not 336 h (`bin/claude-accounts`)

```diff
+# B4: --place reads three apply_burn outputs and nothing else: burn_5h_ph (2 h), burn_5h_ewma_ph
+# (SU_EWMA_LOOKBACK_H) and wk_strand_pp (burn_wk_ewma_ph, WK_EWMA_LOOKBACK_H). The 336 h read exists
+# for burst_percentile and exchange_rate, which only the board renders. One hour of slack covers
+# _util_tail_read's 60 s stop rule and the gap between the read's clock and apply_burn's.
+PLACE_BURN_LOOKBACK_H = max(SU_EWMA_LOOKBACK_H, WK_EWMA_LOOKBACK_H, 2.0) + 1.0
+
+def _place_burn_samples():
+    """The utilization rows --place's burn fields can see, or None (apply_burn's own full read)
+    with CC_PLACE_BURN_NARROW=off."""
+    if not _term_on("CC_PLACE_BURN_NARROW"):
+        return None
+    return _util_tail(hours=PLACE_BURN_LOOKBACK_H)[0]
 ...
-    apply_burn(rows, cfg)
+    apply_burn(rows, cfg, samples=_place_burn_samples())
```

The new block goes just above `cmd_place` (`:6504`). It is placed after `SU_EWMA_LOOKBACK_H`
(`:5244`) and `WK_EWMA_LOOKBACK_H` (`:5301`), so it is derived from the estimators' own constants
and cannot drift from them. `apply_burn`'s other callers are untouched.

**Why it is exact.** M, `/tmp/b4/fieldreads.py`: every read of every `apply_burn` output, by
enclosing function. On `cmd_place`'s call graph there are exactly three:

| Field | Read at | Lookback |
|---|---|---|
| `burn_5h_ewma_ph`, `burn_5h_ph` | `_su_projected` `:4573`, `:4577`; `floors_ok` `:6623-6624` | ≤ `SU_EWMA_LOOKBACK_H` = 6 h, and 2 h for the pair (`:4869`) |
| `wk_strand_pp` | `_strand_cliff_factor` `:3764` | Built from `burn_wk_ewma_ph`, ≤ `WK_EWMA_LOOKBACK_H` = 48 h (`:5301`, `:5342`) |

`burst`, `exchange_k`, `burn_ratio`, `burn_wk_flat_ph` and the rest are read only by `pace_line`
and `dispatch_floor_row`. `cmd_place` never calls either: it calls `score_general` and
`score_fable` directly, not `ranked()`.

### C3. `_util_tail_read` stops once it has reached back past the cutoff (`bin/claude-accounts:4683-4745`)

```diff
     def _parse(lines, out):
+        """-> True when a dated row older than the cutoff was seen: the read reached back past it.
+        Stale rows count for that (their stamp is still a time on the file) and are then dropped."""
+        crossed = False
         for ln in lines:
             try:
                 e = json.loads(ln)
             except (json.JSONDecodeError, TypeError):
                 continue
-            if e.get("stale"):
-                continue
             try:
                 t = datetime.fromisoformat(str(e.get("ts")).replace("Z", "+00:00")).timestamp()
             except (ValueError, TypeError):
                 continue
             if t < cutoff:
+                crossed = True
                 continue
+            if e.get("stale"):
+                continue
             e["_t"] = t
             out.append(e)
+        return crossed and _term_on("CC_UTIL_TAIL_CROSS")
-    out = []
+    out, reached = [], False
 ...
-                    _parse(f.readlines(), rows)
+                    reached = _parse(f.readlines(), rows)
             except OSError:
-                rows = []
+                rows, reached = [], False
 ...
-            if rows and min(r["_t"] for r in rows) <= cutoff + 60:
+            if reached or (rows and min(r["_t"] for r in rows) <= cutoff + 60):
                 break
 ...
-    if not out or min(r["_t"] for r in out) > cutoff + 60:
+    if not reached and (not out or min(r["_t"] for r in out) > cutoff + 60):
 ...   (both sibling arms)
-                        _parse(f.readlines(), out)
+                        reached = _parse(f.readlines(), out)
 ...
-            if out and min(r["_t"] for r in out) <= cutoff + 60:
+            if reached or (out and min(r["_t"] for r in out) <= cutoff + 60):
                 break
```

**Same rows.** In a time-ordered file, a slice that holds a row older than the cutoff holds every
row at or after it. M: 0 of 56,630 rows are out of order. Today's rule assumes the same order; it
just fails to see it. The old 60 s test stays as an OR, so the new rule can only stop **at or
after** where the old one could have stopped.

### R1. The reconciler sends the map, computed from its kept index (`scripts/limit-recover/lr_recon/`)

**`types.py` `Mover` (`:841-853`).** One optional field, last:

```python
    holds: Optional[Dict[str, bool]] = None  # B4: {acct: its store holds a live <sid>.jsonl}
```

`plan.place` serializes with `{k: v for k, v in T.to_dict(m).items() if v is not None}`
(`plan.py:305`), so an absent map changes no byte of today's movers file. That is pinned by
`test_plan.py:100-117`. `Mover` is constructed only at `plan.py:271` and is never `from_dict`'d
(M: `grep -rn "T.Mover("`).

**`transcript.py`.** After `in_projects` (`:320-327`):

```python
def recheck_in_projects(cfg: str, name: str) -> Optional[List[str]]:
    """``<cfg>/projects/*/<name>`` from this thread's pass index after its once-per-name full mtime
    walk (``ProjectsIndex.recheck``), so the first answer for a name is the glob's. None when no
    index is open on this thread: the caller must not glob in its own loop (B4)."""
    active = _ACTIVE
    if active is None or active[1] != threading.get_ident():
        return None
    return active[0].recheck(cfg, name)
```

**`plan.py`.** After `movers()` (`:214-284`); add `import dataclasses` and
`from lr_recon import transcript` (no cycle: `transcript` imports only `clock` and `types`).

```python
def with_holds(mvs: Sequence[T.Mover], amap: Dict[str, str]) -> List[T.Mover]:
    """B4: each mover's ``holds`` map, {account: its store holds a live ``<sid>.jsonl``} for every
    account in ``amap``, from the pass's ProjectsIndex, so ``--place`` never globs
    ``projects/*/<sid>.jsonl`` (one lstat in each of ~18,300 project dirs per store, per mover,
    per account). A mover goes without a map, and --place globs as before, when
    LR_RECON_PLACE_HOLDS=off, ``amap`` is empty, or no index is open on this thread."""
    if os.environ.get("LR_RECON_PLACE_HOLDS", "on") == "off" or not amap:
        return list(mvs)
    out: List[T.Mover] = []
    for m in mvs:
        h: Dict[str, bool] = {}
        for acct, cfg in sorted(amap.items()):
            hits = transcript.recheck_in_projects(cfg, m.sid + ".jsonl")
            if hits is None:
                return list(mvs)
            h[acct] = bool(hits)
        out.append(dataclasses.replace(m, holds=h))
    return out
```

**`__main__.py` `_plan` (`:997-1047`).** Two changes:

- After `if not mvs: return 0` (`:1002-1003`):
  `mvs = plan.with_holds(mvs, _amap(ctx.home))`. `_amap` is `:152-163`.
- In the `place` event detail (`:1022-1036`), append `" holds=%d/%d" % (sum(1 for m in lane_mvs if
  m.holds is not None), len(lane_mvs))`. Then every placement says which path it took.
  `test_main.py:1684-1692` reads the detail with `assertIn` per token, so an appended token breaks
  nothing.

**Why the index answer is the glob's.**

- `_plan` runs inside `run_pass`'s `transcript.pass_index(ctx.projects)` (`__main__.py:1652-1657`),
  on the daemon's index, which is kept across passes (`6841626b4`, an ancestor of HEAD, M:
  `git merge-base --is-ancestor`).
- `ProjectsIndex` is documented and tested to "give the glob's answer": same entries, no
  dot-names, symlinks followed, `lexists` (`transcript.py:104-110`;
  `tests/test_projects_index.py:88` `test_index_answers_every_lookup_the_glob_answered`).
- `recheck` re-stats every project dir of a store the first time a name is asked, at most once per
  store per pass (`:262-280`). So the first map for a sid is exact.
- After that, the index refreshes from:
  - the source slug, which every pass touches through `find_transcript`'s `touch(slug(cwd))`
    (`:336-343`) and `find`'s `_touched.update` (`:290-293`). Touched names apply in every store,
    so a **same-slug** copy, the one `lr-transplant` refuses, is seen the next pass;
  - a rolling 1/30 slice (`ROLL_PASSES`, `:56`). So a **different-slug** copy that appears later in
    an untouched dir is seen within 30 passes. That is the index's one documented lag (`:100-102`).
- M (`/tmp/b4/idxcost.py`, 10 real reconciler sids × 4 stores): index answer == glob answer:
  True.

**Cost to the daemon.** M, uncontended, load1 268:

| Step | Time |
|---|---|
| First sweep (already paid today at daemon start) | 4.09 s |
| Recheck, 10 new names × 4 stores (once per name per daemon life; at most one walk per store per pass) | 0.50 s |
| Steady state, 40 lookups | 0.01 s |
| The 40 globs it replaces | 9.34 s |

Contended (three walkers): recheck 1.40 s against 77.2 s for 8 globs. `recheck` calls
`clock.step` every 256 dirs and after each walk (`:148-149`, `:279`), so the watchdog's progress
clock keeps moving.

### What B4 deliberately does not do

| Option | Why not |
|---|---|
| A precomputed rank cache, stale-while-revalidate, or a fallback ranking | `--place` is the ONLY scorer (`plan.py:3-5`). B2 already ruled that a stale answer is a second scorer needing a ruling under B4/D1 (B2 §13). It is not needed: the scorer itself costs ~0.1 s (M: the prototype's whole run is 0.15 CPU-s). It would also break the cache invariant "burn_* must never reach the cache" (`_render_board` docstring, `:7996-7997`; axis 06 L8) |
| Calling the scorer in-process from the daemon | It loses the subprocess boundary: the kill on timeout and the isolation of an 11.6k-line module from the daemon. It would save only interpreter start-up, ~0.1-0.4 s at priority 31 |
| `place_timeout`'s load term (`plan.py:358-364`) or async `--place` | B2 owns both (B2 S2.b fixes the async bound at 120 s). B4 only makes the child fast |
| The `.handed-off` divergence | `lr-fleet.sh:_lf_target_holds_sid` (`:670-681`) treats `<sid>.jsonl.handed-off` as "holds"; `--place` never did. B4 preserves `--place`'s predicate exactly and flags the divergence (§12) |

---

## 3. Data and format changes

**`--movers` JSONL row.** Gains an optional `holds: {"<acct>": true|false, …}`.

- **Old `--place`, new reconciler.** The key is kept and ignored (`_place_load_inputs` keeps
  unknown keys, `holds()` globs).
- **New `--place`, old reconciler.** No key, so it globs.
- **Rig fake.** `tests/rig/fake-claude-accounts.py:63-112` reads only `sid`, `src` and `w`.
- Compatible in both directions, so the two halves can go live in either order.

**`place` event detail.** Gains `holds=k/n`.

**Unchanged.** No file, cache or ledger format changes. No new state file.

---

## 4. Correctness guarantees and their proofs

| # | Guarantee | Proof |
|---|---|---|
| G-B4.1 | For any input whose map equals the glob's answer, `--place` prints byte-identical JSON and the same rc as today | M: 40 randomized cases (1-9 movers, real multi-store sids, kwork including `None` and near-KMAX, 0-2 facts of 7d/5h/model:opus, weights 1-12, map/no-map) on frozen cache, util and ledger copies with a frozen clock: **0 mismatches** (`/tmp/b4/diff4.py`). Test P7 (§6) |
| G-B4.2 | The reconciler's map equals the glob at its first computation for a sid. Afterwards it is fresh each pass for a same-slug copy and lags at most `ROLL_PASSES` passes for a different-slug copy | `ProjectsIndex` contract and tests (`transcript.py:84-110`, `test_projects_index.py:258`, `:273`). M: index == glob for 10 real sids. Tests R1-R4 |
| G-B4.3 | The three burn fields `--place` reads are bit-identical between the 336 h read and the 49 h read | M: 57 frozen moments, every 6 h over 14 days × 4 accounts × 4 fields = 912 comparisons, **912 identical, all present** (`/tmp/b4/burnprop.py`). Power check: a 24 h window gives 72 of 192 differing. Tests P5, P6 |
| G-B4.4 | `_util_tail_read` returns the same row list under the new stop rule for a time-ordered file, and stops no earlier than the old rule could | M: identical kept rows for 6 spans on the live copy; 0 rows out of order. Tests U1-U4 |
| G-B4.5 | `--place` performs no `projects/*` lookup when every mover carries a complete map, and its utilization parse is bounded by the span, not by the file | Test P1 and the end-to-end E1 (both red today) |

---

## 5. Failure modes under permanent 15-40/core

None of these waits for load; none turns our own timeout into a verdict.

| Failure | What happens | Bounded by |
|---|---|---|
| No map (old reconciler, `LR_RECON_PLACE_HOLDS=off`, `accounts.json` unreadable so `amap` is `{}`, or no index on this thread) | `--place` globs, today's exact behaviour | The 120 s bound, as today. C2 and C3 still cut ~35% of CPU |
| A partial or malformed map | Only the missing or non-bool accounts are globbed | Same |
| A different-slug copy appears after the first recheck, in an untouched dir | For ≤ 30 passes the map says "does not hold". `--place` may place there. `lr-transplant` proceeds (same slug absent), so the target gets two copies, and a **later** hop off it is refused "multiple copies" (`lr-transplant.sh:874`) | Who would write it: only a process running that sid under the target account in another cwd, that is, a second driver, which the claim and fence exclude. M: 0 of 24 multi-store sids use different slugs. Pinned by test R4 |
| A buggy producer says `false` while the target holds the sid at the same slug | `lr-transplant` refuses `already exists` (`:883-884`). The attempt is NOTMOVED. Next pass the slug dir is touched, so the map turns `true` | One attempt |
| Daemon restart | The new index sweeps on its first pass. That is today's cost: 4.09 s uncontended, 210 s with three walkers contending (M). Every live mover is rechecked once | Once per daemon life. A6 governs when restarts happen |
| A recheck walk lands in a busy pass | ≤ one stat per project dir per store, ~0.5-1.4 s (M), stepping every 256 dirs | Once per store per pass, and only when a new mover name appears |
| The utilization log rotates (E ~2026-11-13) | With C3, a span the live file does not cover reads the newest sibling and stops once it crosses the cutoff | The span, not the retained history |
| The utilization log is missing, empty or unreadable | `[]` → `apply_burn` returns early (`:4857-4858`) → the same fields are absent as today | — |
| The log is out of order | Both rules assume order. The new one stops no earlier than the old | M: 0 inversions |
| The cache is older than its 600 s grace | rc 3 → WAIT_DATA → one background `--fresh` sweep (`plan.py:378-398`), as today. B4 does not touch it | M: rc 3 occurred 0 times in 244 events |
| `--place` still overruns its bound (a wedged interpreter, kernel stalls of the 1,226 s `ps` class, axis 03 F9) | rc 124 → `keep_waits` keeps a waiting mover for 3 misses (`plan.py:367-375`). B2's async lane keeps the loop moving | As today |
| `--place` in the background band (a regression of A1) | Still ~1-2.5 s for the prototype, against 54-65 s for the original (M, `taskpolicy -c utility`, which read PRI 20) | — |

---

## 6. Test plan

Every red-before-fix case is marked **[RED]**. "Equivalence guard" cases pass before and after;
each names the mutant that must turn it red ("Green in both arms",
`agent-operating-lessons-situational.md:62`).

### `tests/claude-accounts-place.bats`

Uses the existing `$LOAD` / `place()` harness (`:46-78`), which is hermetic for SSOT, cache,
util, ledger and records.

- **P1 [RED].** "A complete holds map answers the store check: `--place` globs no project dir."
  - Spy on `ca.glob.glob`, recording patterns that contain `/projects/`.
  - Rows `a`, `b`, `c`; three movers with `src="a"`; every mover carries
    `holds={"a": False, "b": False, "c": False}`; `stores={"b": ["s00"]}`.
  - Assert rc 0 and the spy empty.
  - Today: 3 movers × 2 accounts = 6 globs → red.
- **P2 [RED].** "The map is the answer, not decoration."
  - Only `b` has room: `a` has a 7d fact. Disk: `b` holds `s00`. Map: `b: False`. Assert `s00` is
    placed on `b`. Today: `store-holds-sid` → red.
  - Inverse: disk empty, map `b: True` → `store-holds-sid`, with its eta from the fact.
- **P3** equivalence guard. "An account the map omits is globbed."
  - Map `{"a": False}`, disk `b` holds `s00`, only `b` has room → `reason ⊇ store-holds-sid`.
  - Mutant: `holds()` reading a missing key as `False` → red.
- **P4.** "`CC_PLACE_HOLDS_MAP=off` ignores the map." P2's fixture with the switch off →
  `store-holds-sid`.
- **P5 [RED].** "`--place` reads `PLACE_BURN_LOOKBACK_H` hours of the series, not 336."
  - Spy on `ca._util_tail` and assert one call with `hours == ca.PLACE_BURN_LOOKBACK_H == 49.0`.
  - Today: `hours=336` and no such attribute → red.
- **P6** equivalence guard with power. "The burn fields `--place` reads are identical under the
  narrow read."
  - Synthetic 20-day series: 4 accounts, bursty, with 5h and weekly rolls and stale rows.
  - At 20 frozen moments, `apply_burn` with the default read and with
    `samples=_util_tail(hours=PLACE_BURN_LOOKBACK_H)[0]` agree on `burn_5h_ph`,
    `burn_5h_ewma_ph`, `burn_wk_ewma_ph` and `wk_strand_pp`, and each is present on at least one
    row.
  - Mutant: `PLACE_BURN_LOOKBACK_H = 24.0` must differ (M on live data: 72 of 192 differ).
- **P6b** reachability guard (python `ast`, no execution).
  - Collect the keys `apply_burn` writes (`r["k"] = …`).
  - Collect every `.get("k")` / `["k"]` read in `cmd_place` and its nested defs, and transitively
    in every module-level function they call by name.
  - Assert the intersection ⊆ `{"burn_5h_ph", "burn_5h_ewma_ph", "wk_strand_pp"}`.
  - Mutant: add `r.get("burst")` to `floors_ok` → red. This catches a future reader that needs a
    window wider than 48 h.
- **P7** equivalence guard. Differential property test: 30 seeded fixtures (movers 1-9, weights
  1-12, kwork including `None`, facts, `stores` with copies in 0-3 accounts).
  - `cmd_place` with maps computed by the glob == `cmd_place` without maps, byte for byte.
  - Mutant: flip one map bit → at least one answer differs.
  - This is the hermetic form of my `/tmp/b4/diff4.py`.
- **E1 [RED].** End-to-end contract, the headline control: "a 9-mover batch with complete maps does
  0 `projects/*` lookups and ≤ 5,000 `json.loads` on a 20-day bursty series of ≥ 40,000 lines."
  - Wrap `ca.json` with a counting `loads` for the call; keep the glob spy from P1.
  - Today: 9 × 3 globs and ~2× the file in `json.loads` → red.

### `tests/claude-accounts-util-tail.bats`

Uses the existing `$LOAD` and `rec()` (`:29-46`).

- **U1 [RED].** RP-9 "A read that crossed the cutoff stops."
  - 20 days of bursts (4 rows sharing one `ts` every 5 min), offset so the cutoff falls 2.5 min
    from the nearest burst on each side.
  - `_util_tail(path=p, hours=48)` returns exactly the brute-force rows (`t ≥ cutoff`, not stale),
    with `json.loads` count ≤ 4 × the rows kept.
  - Today: the whole file ×~2 → red.
- **U2 [RED].** RP-10 "A rotated history is read only as far back as the span."
  - Live file 3 h; three `.gz` siblings of 60 h each, newest by mtime as `rotate-autonomy-logs`
    names them.
  - A 48 h read opens exactly one sibling (spy on `ca.gzip.open`) and returns the brute-force rows.
  - Today: 3 opens → red.
- **U3.** `CC_UTIL_TAIL_CROSS=off` restores the old slice count on U1's fixture. This pins the
  kill switch.
- **U4** equivalence guard.
  - Spans {0.5, 2, 6, 48, 49, 72, 336, 400} h × fixtures {evenly spaced, bursty, with stale rows,
    with unparseable lines, short live file + siblings}: rows identical with the switch on and off.
  - Mutant: break after the first slice unconditionally → spans past the seed differ.
- RP-6, RP-7, RP-8, RP-8b and RP-8c stay unchanged and green.

### `scripts/limit-recover/lr_recon/tests/test_place_holds.py` (new)

Reuses `test_projects_index.Tree`: a symlinked `.claude-next` store, a dot-dir, a dangling symlink,
a file directly under `projects/`, the same sid under several slugs.

- **R1.** Inside `transcript.pass_index(ProjectsIndex(step_fn=noop))`, `plan.with_holds(movers,
  amap)` gives `holds == {acct: bool(old_glob(cfg, sid + ".jsonl"))}` for every SID × store.
- **R2.** With no index open (a bare call), the movers come back unchanged with `holds is None`.
  `plan.place`'s movers file then has no `holds` key (`FakeRun`, as in `test_plan.py:105`).
- **R3.** `LR_RECON_PLACE_HOLDS=off` → unchanged. An empty `amap` → unchanged.
- **R4** pins the residual. After the first map:
  - a copy created at the source's slug in another store is `True` on the next pass;
  - a copy created in an old untouched dir is `True` within `ROLL_PASSES` passes and may be
    `False` before.
- **R5** cost. With `stat_fn` and `scandir_fn` counters:
  - 9 movers × 4 stores on pass 2 make ≤ one full stat walk per store;
  - pass 3 makes none beyond the slice and the hot set.
  - Mutant: call `recheck` with a fresh index each mover → red.
- **R6** (`test_plan.py`). A mover with `holds` set round-trips into the `--movers` file;
  `test_place_argv_and_parse` (`:105-117`) stays green unchanged.
- **R7** (`test_main.py`). The `place` event detail carries `holds=` (next to the existing token
  checks at `:1684-1692`).

### Ratchets before `/ship`

From `agent-operating-lessons-situational.md:256` and `:260`:

- `bash scripts/test-afunix-path-lint.sh`
- `bash scripts/test-hermeticity-lint.sh`
- `python3 scripts/bats-assert-liveness-fix.py tests/claude-accounts-place.bats tests/claude-accounts-util-tail.bats`
- bare `shellcheck` on both `.bats` files
- the duplicate top-level-name `ast` check for `bin/claude-accounts`. M today: no name the design
  adds exists yet: `PLACE_BURN_LOOKBACK_H`, `_place_burn_samples`, `recheck_in_projects`, `with_holds`.
- the existing suites:
  - `bats tests/claude-accounts-place.bats tests/claude-accounts-util-tail.bats tests/claude-accounts-strand.bats tests/claude-accounts-core.bats tests/rig-stub.bats`
    (serially; `bats --jobs` without GNU parallel runs nothing, `:254`);
  - `cd scripts/limit-recover && python3 -m unittest discover -s lr_recon/tests -t .`

### Verify under load (rule `:83`)

**Immediately, read-only, agent-runnable.** This is the same-moment A/B I ran (§7). Nothing writes
outside `/tmp` (`CLAUDE_ACCOUNTS_LOG` redirected; `--max-wait 0` is cache-only):

```
CLAUDE_ACCOUNTS_LOG=/tmp/b4v/ca.log PYTHONDONTWRITEBYTECODE=1 /usr/bin/time -p \
  ~/.claude/bin/claude-accounts --place --lane general --recovery --movers /tmp/b4v/movers9-map.jsonl \
  --facts /tmp/b4v/facts --kwork /tmp/b4v/kwork.json --json --max-wait 0
```

Print `sysctl -n vm.loadavg` beside each run, as the positive control that the load is present.

**After R1 is live.** The next cohort's `place` events. Accept when, over ≥ 20 events at
load1 ≥ 150:

- every event reads `holds=n/n`;
- answered p95 `dur` ≤ 5 s;
- there are 0 rc 124.

The check: `grep '"ev":"place"' ~/.reso/limit-recover/recon/events.jsonl | tail -40`.

**B1.** Replace the rig placer's `cpu_s` 4.0 (B1 §9.3, from axis 06) with the measured 0.15 CPU-s
per call.

---

## 7. Prototype evidence

Everything below ran under `/tmp/b4`. Prototype 2 is `bin/claude-accounts` with C1+C2+C3 applied
by `/tmp/b4/mkproto.py` and `mkproto2.py` (40 insertions, 14 deletions; `/tmp/b4/proto2.diff`).
R1 was not prototyped as code; its index answers were measured directly (`/tmp/b4/idxcost.py`).

| Run | Result (M) |
|---|---|
| Real CLI, original, 3 movers, priority ~31, load1 243-260 | 7.19 / 8.80 / 13.98 s |
| Real CLI, original, 3 movers, load1 142-151 (uncontended) | 2.87-5.85 s |
| Real CLI, original, 9 movers, load1 156-185 | 8.67-11.73 s |
| Real CLI, prototype 2 + map, 3 movers, load1 195 | 0.32-1.59 s |
| Real CLI, prototype 2 + map, 9 movers, load1 195-199 | 0.25-0.56 s |
| CPU per call, 9 movers, load1 165-169 (`/usr/bin/time -p`) | original real 4.75-10.33 s, user 1.58-1.67 + sys 2.68-3.19; prototype real 0.15-0.17 s, user 0.12-0.13 + sys 0.02 |
| Band 20 (`taskpolicy -c utility`, read back `ps -o pri=` 20), 3 movers | original 64.5 / 54.0 s at load1 206-247; prototype 2.5 / 1.1 s at load1 266 |
| Prototype 1 (C1+C2, no C3) + map, 9 movers | 0.30-0.78 s. Its profile still showed 9 slices / 144,639 `json.loads` for `hours=49`, which is how C3 was found |
| Differential v4: isolated, frozen clock and inputs, 40 cases | 0 mismatches; 78 true holds entries supplied. In-process per call: map mode 3.70 → 0.12 s, no-map mode 2.85 → 1.30 s |
| Red control (same harness) | `07e30aeb` with a truthful map → `placed` on `next`; with an all-true map → `fact:7d,store-holds-sid`. The map is consulted |
| Burn property, 912 comparisons | 912 identical. Mutant at 24 h: 72 of 192 differ |
| Index vs glob, 10 real sids × 4 stores | equal; recheck 0.50 s against glob 9.34 s |

**Discarded runs**, reported because they could mislead:

- **Differential v1/v2.** Their `eta_s` mismatches (1-2 s apart) came from my harness: each arm
  rewrote the facts with a fresh `time.time()`, and the arms ran seconds apart. Fixed in v3/v4 by
  freezing `time.time`.
- **v2 and v3 ran concurrently on shared scratch paths.** v3's trials 9 and 11 saw a `fact:5h`
  that the other run had written between the arms. v4 used private paths and ran alone.

---

## 8. Rollout and kill switches

1. **One branch, one `/ship`.** C1+C2+C3 in `bin/claude-accounts`; R1 in `lr_recon`
   (`types.py`, `transcript.py`, `plan.py`, `__main__.py`); the tests of §6.
2. **Converge** (`CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`). C1-C3 are live at the
   next `--place` call, because `~/.claude/bin/claude-accounts` is a symlink into the checkout
   (M: `ls -la`). C2 and C3 act at once. C1 is inert until a map arrives. C3 also speeds up every
   `--rank` / `--route` / board render.
3. **R1 goes live at the reconciler's next restart.** The running daemon has `lr_recon` imported.
   - Natural restarts are frequent (M: 12 rows in `restarts.jsonl` since 10-18, the latest at
     16:04:56Z).
   - **Do not force one in the middle of a cohort** (A6).
   - `lr-band-reload.sh` already waits for no `lr-recon-act` child (its header, lines 10-11).
4. **Verify** with the first cohort's `place` events (§6).

**Kill switches.** Each is read on every call, default on, and follows the repo's `_term_on`
convention:

| Switch | Effect |
|---|---|
| `CC_PLACE_HOLDS_MAP=off` | `--place` ignores maps and globs |
| `CC_PLACE_BURN_NARROW=off` | 336 h read |
| `CC_UTIL_TAIL_CROSS=off` | Old stop rule |
| `LR_RECON_PLACE_HOLDS=off` | The reconciler sends no map |

For the daemon these need its plist environment, which is an operator step.

**The fast rollback is agent-side and needs no restart.** Revert the `bin/claude-accounts` hunks
and converge. `--place` then globs again, and the reconciler's maps become inert.

---

## 9. Operator steps

**None required.** Optional: if the operator wants R1 live before the next natural restart, at a
moment with no open cohort:

```
bash ~/Development/claude-infrastructure/scripts/limit-recover/lr-band-reload.sh --confirm lr-band
```

It reloads the reconciler and the reset poller, waits for no actuator child first, and reads the
band back.

---

## 10. Estimated LOC

E: by the prototype diff, plus sketches.

| Part | Code | Tests |
|---|---|---|
| C1 (+ docstring) | 12 | P1-P4, P7: 90 |
| C2 | 14 | P5, P6, P6b: 80 |
| C3 | 16 | U1-U4: 90 |
| R1 (`types` 1, `transcript` 10, `plan` 22, `__main__` 6) | 39 | R1-R7: 130 |
| E1 | — | 30 |
| **Total** | **≈ 80** | **≈ 420** |

---

## 11. Dependencies on other items

**None blocks B4.**

| Item | Relation |
|---|---|
| A1 (landed, `07ce89a99`) | All measurements here assume priority 31. B4 also removes most of the band-20 risk (§7) |
| A6-restart-safety | Governs **when** R1 goes live: the next restart, never forced mid-cohort. Not a code dependency |
| B2-bounded-pass | Complementary. B2 stops the loop waiting on `--place` and owns `place_timeout`; B4 shrinks the call. B2 §12 says the same |
| B3-deadline-override | B3's F9 ("`--place` times out for a never-placed overdue record") is fixed only by B2 or B4 |
| B1-load-harness | Takes B4's measured 0.15 CPU-s per call as the rig placer's `cpu_s`. B4's own verification does not need B1 |
| B6-telemetry | Independent. B6's child timing `ch["claude-accounts --place"]` will show the drop; B4 adds `holds=k/n` to the event |
| G2-self-recovery, D1-repick-ruling | Benefit from C3. Their `--rank` pays the same whole-file parse today (G2 §9 notes a cheaper `--rank` helps its S6) |
| D2-warning-band-shedding | Benefits: more movers per `--place` cost nothing extra |
| B5, B7, B8, C1, C2, A7 | None |

---

## 12. Risks and residuals

1. **The different-slug lag** (§5 row 3). This is the one place where the map can be stale while
   the glob would not be. Its consequence lands on a **later** hop, as "multiple copies"
   (`lr-transplant.sh:874`), not on this one. M: 0 occurrences in today's corpus. Pinned by R4,
   so any change to it is deliberate.
2. **C3 changes a reader shared with the board, keepwarm, `--rank` and `--route`.** It is
   output-identical by construction and by replay (§1.4, U4), and has its own switch. The
   "new def shadows a helper" lesson (`:256`) is covered by the duplicate-name check.
3. **Two predicates answer the same question.** `lr-fleet`'s `_lf_target_holds_sid` counts
   `.handed-off`; `--place` does not. B4 keeps `--place`'s semantics. Whether `--place` should
   also avoid a target that holds only a tombstone is outside B4: `lr-transplant`'s return-hop
   sweep handles that case (`lr-transplant.sh:351-400`).
4. **The urgency is lower than when B4 was ranked.**
   - At priority 31 the original already answers in 3-20 s here, against a 120 s bound.
   - B4's value is now to remove the growth terms: project dirs, retained log history and the
     coming rotations; to remove the contention sensitivity (a glob went from 0.23 to 9.7 s when
     other walkers ran); to cut ~4.5 kernel-heavy CPU-s per call at priority 31; and to shorten
     the pass's serial time for B2 and B3.
   - "Cause refuted ≠ effect discharged" (`:35`): this is not proof that `--place` can never
     time out again, only that its own work is no longer the reason.
5. **No priority-31 production sample yet** (§1.3). The verification in §6 closes that at the next
   cohort.

---

## 13. Conviction: 85%

**For.** An exact, measured mechanism for both dominant terms. An output-identical prototype:
0 of 40 mismatches with real positive cases, and 912 of 912 field comparisons identical with a
mutant that has power. A 20-60x reduction in wall time and ~30x in CPU at today's load. An index
that already exists, is tested and runs in the daemon. No operator ruling.

**Against.**

- The different-slug residual.
- C3's blast radius across every ranking verb, although it is output-identical.
- R1 is not prototyped as code. Its index answers were measured; its wiring into `_plan` was not
  run.
- The production effect at priority 31 is unmeasured until a cohort occurs.

---

## Appendix: commands run

All read-only, or writing only under `/tmp/b4`.

| Command | What it established |
|---|---|
| `git diff --stat 28b25a119 HEAD -- bin/claude-accounts …` (shared checkout) | The worktree's `claude-accounts` equals `main`'s |
| `sed -n`/`grep -n` on `bin/claude-accounts`, `lr_recon/{plan,__main__,transcript,types,census}.py`, `lr-transplant.sh`, `lr-fleet.sh`, `lr-move-lib.sh`, `rotate-autonomy-logs.sh`, `store-bounds.manifest`, the tests | All file:line citations |
| `ls -1 <cfg>/projects \| wc -l` × 5 | 18,197-18,406 project dirs per store |
| `ls -la /tmp/claude-accounts-cache.json ~/.claude/logs/account-utilization.jsonl*`; `wc -l account-assignments.jsonl` | 4.6 KB cache; 19.47 MB log, no rotated siblings; 207-line ledger |
| python over `recon/events.jsonl{,.1}` `place` rows | 244 events, 17 rc 124, medians by load; none after 05:25:15Z |
| `cat recon/heartbeat`, `tail recon/band.log`, `restarts.jsonl` | The daemon at priority 31; restart cadence |
| `bash /tmp/b4/run.sh`, `/tmp/b4/run2.sh` (real CLI, cache-only, log redirected) | Wall times with load1 |
| `python3 -m cProfile … bin/claude-accounts --place …` and the prototype | §1.2 profile; the prototype's residual |
| `/usr/bin/time -p` × 6; `taskpolicy -c utility` × 4 | CPU per call; the band-20 arm |
| `python3 -I /tmp/b4/fieldreads.py` | The burn fields read on `--place`'s path |
| `python3 -I /tmp/b4/xstore.py` | Cross-store copies: 24, 0 at different slugs |
| `python3 -I /tmp/b4/utiltail.py` | The stop-rule replay (§1.4) |
| `python3 /tmp/b4/diff4.py … 40 /tmp/b4/proto2/claude-accounts` | Differential: 0 of 40 |
| `python3 /tmp/b4/burnprop.py` (+ the 24 h mutant) | Burn equivalence and its power |
| `python3 -I /tmp/b4/idxcost.py` (10 sids) | Index == glob, and its cost |
| `git merge-base --is-ancestor 6841626b4 HEAD` | The kept index is in HEAD |

Nothing was typed into a pane, signalled, loaded, or edited in the repo or in live state. My own
measurement processes ran to completion under their own `timeout` bounds.

---

## Review — efficacy-under-permanent-load

**Reviewer's lens.** Does B4 bound recovery time at 15-40 runnable per core, with every lane at
PRI 31? Does any new wait, bound or gate assume that load falls?

**Method.** Read-only. Code at `28b25a119`. Scratch files only under `/tmp/b4rev/`, plus a
read-only use of the designer's `/tmp/b4/` artefacts. Labels: M = measured (command named),
E = estimated (method named), H = hypothesis.

**Verdict: NEEDS-CHANGES. Adjusted conviction 78% (design: 85%).** The mechanism holds. B4 adds
no wait keyed to load. But one test cannot pass as written, the rollout waits for a lull, and the
new loop-thread work is neither declared nor observable. Four claims are overstated. The design
also leaves out one residual that limits how much B4 can bound recovery.

### V. What survives verification

- **Citations.** I spot-checked about 35 `file:line` claims. All hold. Among them:
  - `holds` at `:6637-6638` / `:6658`, and the stop test at `:4722` after the drop at `:4695`;
  - `apply_burn`'s 336 h read at `:4856`, `place_timeout` at `plan.py:358-364`, and the
    serialiser at `plan.py:305`;
  - `recheck` at `transcript.py:262-280`, `ROLL_PASSES` at `:56`, and the refusals at
    `lr-transplant.sh:869-885`;
  - the event-detail asserts at `test_main.py:1684-1692`, and the rotation settings at
    `rotate-autonomy-logs.sh:75`, `:450` and `store-bounds.manifest:47`.
- **No load term.** M: `grep -n getloadavg bin/claude-accounts` finds only `:8051`, inside
  `_local_board`. `/tmp/b4rev/paths.py` does a BFS over `cmd_place`'s static call graph and
  reports `_local_board unreachable`. C1, C2, C3 and R1 each do a fixed amount of work. None
  polls, sleeps or gates on load. The fixed `get_data(max_wait=0)` path raises before any lock
  (`:8253-8259`), so no `ps` or sweep runs, although the static graph reaches them.
- **C2 is exact.** M: `python3 -I /tmp/b4rev/callgraph.py` over 183 reachable functions.
  - Outside `apply_burn`, only three of its outputs are read: `burn_5h_ewma_ph` (`:4573`,
    `:6623`), `burn_5h_ph` (`:4577`, `:6624`) and `wk_strand_pp` (`_strand_cliff_factor` `:3764`).
  - `wk_strand_pp()` (`:5399-5421`) reads only `weekly_pct`, `weekly_reset_h` and
    `burn_wk_ewma_ph`.
  - `exchange_k` (`:4955`) is read only in `pace_line` (`:5916`), which is unreachable from
    `cmd_place`.
- **The C3 defect is real.** M: `python3 -I /tmp/b4rev/stoprule.py` runs the original code on a
  frozen 19,490,876 B copy at load1 166. For 6 h, 48 h, 49 h, 72 h and 336 h it does 143,795
  `json.loads` each.
- **C3's order precondition holds by construction.** `record_utilization` has one call site,
  `:8319`, inside `get_data`'s single-flight `flock`. It stamps `ts = now` at write time
  (`:7124`).
- **R1's walk count is bounded.** `recheck` walks a store at most once per pass
  (`st.full`, `transcript.py:271-279`): at most one `stat` per project dir per store per pass,
  however many movers there are. It steps the watchdog clock every 256 dirs (`:146-149`).
- **C1 and R1 target the shape that timed out.** M, a python breakdown of the 244 `place` events
  in `recon/events.jsonl{,.1}`:

  | Movers | Events | rc 124 | Answered median |
  |---|---|---|---|
  | n = 1 | 167 | 1 | 3.3 s |
  | n = 2-3 | 39 | 13 | 30.9 s |
  | n = 4-9 | 38 | 3 | 5.0 s |

  This fits the design's point that `holds()` runs only for accounts with room (§1.1).

### F. Refutations and corrections

**F1. E1 cannot pass as written.** It requires "≤ 5,000 `json.loads` on a 20-day bursty series
of ≥ 40,000 lines".

- That density puts about 4,100 rows in 49 h. The doubling read parses about 2-4× the rows it
  keeps.
- M: `python3 -I /tmp/b4rev/e1sim.py /tmp/b4/proto2/claude-accounts`, the designer's own C3
  prototype, on 40,188 lines (11,775,084 B, 20 days, 4 rows per burst every 172 s):
  `hours=49 rows=4104 json.loads=13865`.
- So E1 stays red after the fix. That invites someone to weaken it at implementation time.

**F2. G-B4.4 states the guarantee the wrong way round.** It says "stops no earlier than the old
rule could", and C3 says "can only stop at or after".

- The new test is `reached OR old`. So it stops at **the same slice as the old rule or an
  earlier one**.
- The guarantee that matters is different: the read never stops before a slice reaches back
  past the cutoff. On a time-ordered file the kept rows are then identical.

**F3. "Parses the whole file twice on every call" is overstated.**

- M: `python3 -I /tmp/b4rev/phase.py` tested 86,400 call moments, every 7 s over the last 7 days
  of the frozen copy. The whole-file fall-through happens at 86.0% (2 h), 85.5% (49 h) and
  84.9% (336 h) of them.
- At one live moment the original stopped a 2 h read after 301 `json.loads` (stoprule.py).
- Correct claim: on about 85% of calls.

**F4. The rotation bound is "the span rounded up to whole siblings", not "the span" (§5).**

- A `.gz` sibling has no tail seek. `_parse(f.readlines(), out)` in the sibling walk
  (`:4727-4744`) parses the whole sibling.
- After each rotation, a span that crosses into the newest sibling parses all of it. E: about
  76k rows (26,214,400 B / 344 B per row).
- That lasts the first ~49 h after each rotation for `--place`, and the first ~14 days for
  336 h readers. E: the cycle is ~93 days (25 MiB / 281 KB per day).
- This is today's cost class, so it is no regression, but the claim must say it.

**F5. The rollout waits for a lull.**

- §8.3 says "Do not force one in the middle of a cohort". §9 says "at a moment with no open
  cohort".
- A6 says that boundary "may never come" under a standing cohort
  (`A6-restart-safety.md:243-245`).
- `lr-band-reload.sh` gives up after `QUIET_MAX_S=1800` (`:36`) with "nothing reloaded, re-run
  later" (`:158-160`).
- R1 carries the 64% term, so `--place`'s gain depends on R1 going live.
- Today lulls do exist. M: the newest `events.jsonl` row is from 12:01Z, about 6.8 h before
  this review. So this is not blocking. But R1's activation must not depend on a lull.
- A6 §2.6's `recon/ctl/restart.request` restarts the daemon at a pass boundary "at any load"
  (`A6:225-232`). That is the right activation path.

**F6. R1 moves work onto the loop thread, and nothing reports its cost.**

- Today the only `recheck` caller is `transcript.observe` (`:532-541`). It runs on the session's
  own config dir, and only after a slug-direct miss.
- R1 rechecks every new mover in every store. That is new inline work, at most #stores × #dirs
  `stat` calls per pass, and the dir count only grows (§1.3).
- After B2 lands, `--place` runs on a worker (B2 S2.b, `B2:480-535`) and its globs leave the loop
  thread. R1's walk is then the one part of `--place`'s former work still inline.
  - It is outside `PLACE_INLINE_S` (`B2:488`).
  - It is missing from B2's §5 `plan` row (`B2:713`).
- Only two cost points exist, and neither was measured in the daemon or at 30-40 per core:
  - 0.50 s at load1 268 (`/tmp/b4/idxcost2.out`);
  - 1.40 s at load1 **50.95** (`/tmp/b4/idxcost.out`).

**F7. B2's thread rule, with a silent fallback.**

- The design's `recheck_in_projects` returns None off the index's thread. A `with_holds` that
  ends up inside B2's `AsyncCall` worker would send no map (`holds=0/n`), and `--place` would
  glob again without anyone noticing.
- B2 forbids `transcript.*` on workers (`B2:781`). B4 names no insertion point in B2's
  restructured `_plan` (`B2:492-493`).

**F8. The acceptance check is blind above ~27 per core.**

- The prototype was measured at load1 156-199 at PRI 31. Load1 266 was reached only in band 20.
- "≥ 20 events at load1 ≥ 150" can be met entirely at 15-20 per core.
- M: in the last week only 9 production `place` events ran at load1 ≥ 300.

**F9. The different-slug residual is stated in passes, not wall time, and its consequence is
unbounded.**

- E: 30 passes × P. With today's P_max ≈ 14 min (REPORT B3 risk) that is up to ~7 h. After B2 it
  is ~15-100 min (B2 §5's pass estimate).
- The consequence is `lr-transplant.sh:873-874`: "REFUSED — multiple copies … disambiguate
  manually". That session is stuck until an operator acts. It is rare (0 of 24 today), but it is
  not one attempt.

**F10. The same corpus scan stays on the move path, and nothing in the design names it.**

- M: `grep -n 'projects/\*/'` finds about 20 per-sid glob sites in `lr-transplant.sh`,
  `lr-fire-resume.sh`, `lr-handoff.sh`, `lr-ingest-verify.sh`, `lr-move-worker.sh`, `lr-lib.sh`
  and `lr-move-lib.sh`. Examples: `lr-transplant.sh:869`, `lr-fire-resume.sh:377`,
  `lr-handoff.sh:663/965/1073/1295`, `lr-ingest-verify.sh:251/334/366`.
- M: `bash /tmp/b4rev/bashglob.sh` ×3, one such glob over 18,409 dirs at load1 241-247, PRI 29:
  2.41 / 1.16 / 1.28 s.
- How many of these run per move is not measured (H).
- B4 removes only `--place`'s scans. Without this residual on record, "B4 removed the corpus
  scans" reads as covering the move path too, which it does not.

**F11. R1's kill switch needs a restart.**

- `LR_RECON_PLACE_HOLDS`, and `CC_PLACE_HOLDS_MAP` for the daemon's `--place` child, live in the
  plist environment. Changing them needs a reload, which F5 says may need a lull.
- The only rollback without a restart reverts all of C1-C3, which throws away C3's fix for
  `--rank` and the board.

**F12. The "contended" figures were measured at about 5 per core.**

- `idxcost.out` reads load1 50.95 for the 210.12 s sweep, the 1.40 s recheck and the 77.21 s for
  8 globs. The contention came from the designer's own concurrent walkers.
- §1.3, the R1 cost table and §5's "Daemon restart" row omit that load1.

### Required changes

1. **E1.** Replace "≤ 5,000" with a relative bound: `json.loads` ≤ 4 × the rows kept for 49 h,
   plus one seed slice. Alternatively, build the fixture at the live density (~34 rows/h,
   ~16k lines over 20 days). The proto2 count of 13,865 must pass the corrected bound.
2. **Claim corrections.**
   - G-B4.4 and C3 "Same rows": state that the new rule stops at the old rule's slice or an
     earlier one, never before the slice crosses the cutoff, and cite `:8319` and `:7124` for
     order by construction.
   - §0 and §1.4: "~85% of calls (M)", not "every call".
   - §5 rotation row: "the span rounded up to whole siblings: one whole sibling for 49 h (or
     14 d) after each rotation".
   - Add the load1 of 50.95 to every "contended" figure.
3. **Rollout (§8.3, §9, §11).** Drop "no open cohort" and "never forced mid-cohort" as
   preconditions for R1. Activate R1 through A6's `recon/ctl/restart.request` pass-boundary
   restart once A6 lands; until then, the next restart of any cause. List A6's `restart.request`
   as the soft activation dependency.
4. **Declare R1's inline cost.**
   - §5 states it: at most one `stat` per project dir per store, per pass that has a new mover
     name. It grows with project dirs.
   - Hand B2 a line for its §5 `plan` row.
   - Add a `holds_s=%.2f` token (wall time of `with_holds`, walks included) beside `holds=k/n`.
   - Extend R5 to 40 new names in one pass: still at most one walk per store.
5. **B2 placement.**
   - Specify that `with_holds` runs on the loop thread, right after `mvs = plan.movers(...)` in
     B2's `_plan` and before `by_sid`/`_start_place`.
   - Extend R7: with stage 2 on, the movers given to `_start_place` carry `holds`. Mutant: call
     `with_holds` from the worker; `holds` becomes None, so R7 goes red.
6. **Stratify the §6 acceptance by load1:** 150-249, 250-349 and ≥ 350, each band reported with
   its n.
   - Write "unverified at ≥ X" for any band with fewer than 5 events.
   - Ask B1 for a 40-per-core arm that runs the real `--place` on frozen inputs (cache-only,
     log redirected).
7. **§12.1.** State the different-slug lag in wall time (`ROLL_PASSES` × P) and its consequence:
   an operator-only "multiple copies" stuck session. Add a count of `multiple copies of` in
   `recon/actlogs/` to the §6 verification.
8. **§12.** Name the per-sid `projects/*` globs on the move path as a residual with no owner,
   with the measured per-glob cost (F10), so B4 is not read as removing corpus scans from
   recovery.
9. **A kill switch read every pass:** `recon/place-holds.off`, checked by `with_holds`, in the
   pattern of B2's `recon/async.off` (`B2:439`). R1 can then be turned off at any load without a
   restart and without reverting C2/C3.

### Not required, but worth weighing

- **An "exact every pass" variant.** `with_holds` could bypass the per-name `_rechecked` gate but
  keep the per-pass `st.full` gate. That removes the different-slug residual (F9) outright.
  - Cost while movers exist: at most #stores walks per pass. E: ~0.5 s at load1 268 from
    `idxcost2.out`.
  - That is still a small fraction of the globs it replaces.
- **C2's one-hour slack.** Add one sentence: it holds at any load because the parent kills the
  child at ≤ 120 s (`plan.py:55`, `:358-364`). The gap between the read's clock and
  `apply_burn`'s `now` therefore cannot reach 1 h.
- **B1's rig placer.** It should model two costs: map present (0.15 CPU-s) and map absent (globs
  scale with movers × accounts with room). Then a silent `holds=0/n` regression would show up
  in the rig.

### Does B4 bound recovery time under permanent load?

**Partly.** After B4, `--place`'s own work is bounded by the requested span and by the number of
stores. It no longer grows with corpus × movers. No new wait depends on load falling.

It does not by itself bound recovery:

- Until B2 lands, `--place` stays synchronous behind `place_timeout`. That bound is 112.5-120 s at
  15-40 per core: E from `plan.py:363`, `30 × load1 / (4 × 10)`, capped at 120.
- The move path keeps its own corpus globs (F10).
- R1, which carries 64% of `--place`'s cost, is unprototyped. It goes live only at a restart.

With the nine changes above, B4 is a sound and necessary part of the bound. It is not the bound
itself.

---

## Review — correctness-and-safety

**Lens.** Could B4 strand a session, move it twice, lose a draft, split its transcript, break an
invariant or break an existing test?

**Method.** Read-only, code at `28b25a119`. Scratch files only under `/tmp/b4rev/`: harnesses, a
frozen copy of the utilization log, and scratch repos for bats. Bats ran with `TMPDIR` under
`/tmp`. Labels: M = measured (command named), E = estimated (method named), H = hypothesis.
Where the efficacy review above already covers a point, I cite it and add only evidence.

**Verdict: NEEDS-CHANGES. Adjusted conviction 82%.** B4 creates no new path to a double move,
a lost draft or a split-brain. Its one new staleness, an intra-pass window that §4/§5 do not
state, costs at most one refused attempt. Three items need fixing: one outcome is misnamed,
C3's equivalence holds only for a time-ordered log and the doc does not say so, and two tests
cannot do what they claim (E1, U2).

### S. Refutation attempts that failed (the design holds here)

- **C1 changes only the store check.** The prototype diff (`/tmp/b4/proto2.diff`) matches §2
  byte for byte. `holds` is called only from the `elif` at `:6658`. `_place_load_inputs` keeps
  unknown keys (`:6492`). No other program calls `--place`: M, `grep -rln -- '--place' bin
  scripts hooks tests` shows only the reconciler, its tests and the rig fake.
- **C2's field set is exact.** M, `python3 -I /tmp/b4rev/fieldreads.py bin/claude-accounts
  cmd_place`, my own AST walk over 167 reachable functions. `apply_burn` writes 18 keys. Exactly
  `burn_5h_ewma_ph`, `burn_5h_ph` and `wk_strand_pp` are read on the path. M, `/tmp/b4rev/reach.py`:
  `pace_line`, `dispatch_floor_row`, `ranked`, `burst_percentile`, `exchange_rate` and
  `wall_projection` are all unreachable from `cmd_place`, and `_util_tail` is reachable only
  through `apply_burn`.
- **Empty narrow reads are safe.** If the 49 h read is empty, `apply_burn` returns early
  (`:4857-4858`). The 336 h read would also leave all three fields absent:
  - `wk_strand_pp` needs `burn_wk_ewma_ph` (`:5421-5422`);
  - each EWMA filters to its own window (`:5277-5280`, `:5340-5343`).
- **C3 keeps the rows on a time-ordered file.** M: `python3 -I /tmp/b4rev/c3replay.py <orig>
  /tmp/b4/proto2/claude-accounts` on a fresh frozen copy (56,658 rows, 0 inversions), frozen
  clock, spans 0.5 / 2 / 6 / 48 / 49 / 72 / 168 / 336 / 400 / 2000 h:
  - kept rows are identical to the original's and to brute force in all 10 cases, and so is the
    span;
  - `json.loads`: 143,795 originally, against 301 (≤ 6 h), 4,445 (48-72 h) and 39,904 (336 h)
    with C3.
- **The existing suites stay green.** M: `bash /tmp/b4rev/runbats.sh`. The unmutated control
  (original bin) and the C1-C3 prototype each ran in their own scratch repo:
  - `claude-accounts-util-tail.bats`: `1..8`, 8 ok, 0 not ok, in both;
  - `claude-accounts-place.bats`: `1..23`, 23 ok, 0 not ok, in both.
- **No lr_recon test breaks.** M, grep: no `lr_recon` test compares `Mover` lists by equality. The
  exact-row pin at `test_plan.py:113-116` builds `Mover`s directly, never through `with_holds`.
  The `None` filter at `plan.py:305` drops an absent map. `test_projects_index.Tree` has no test
  methods of its own (`:30-86`), so subclassing it in the new module duplicates no tests.
- **A false "does not hold" cannot cause a double move or an overwrite on the reconciler's path.**
  - The reconciler's only first-hop actuator is `cmd_move`, which always passes `--in-place`
    (`act.py:103-131`). That gives `--phase admit` (`lr-handoff.sh:1682`).
  - Admit reaches the arrival refusal "REFUSED — $DST already exists" (`lr-transplant.sh:883-884`)
    before the split-brain lock (`:891`) and before any tombstone.
  - `confirm` does deliberately overwrite an existing target copy (`:531-533`). But a caller that
    names a record must hold an admit's lock (`:524`, `lrt_assert_lock` `:431-433`). The
    reconciler always passes `--record-id`, so a stale map cannot reach that overwrite.
- **No draft risk.** Admit refuses before any `/exit` (`lr-handoff.sh:1666-1691`), so a refused
  hop leaves the source pane and its composer untouched.
- **Rollout in either order is safe.** Old `--place` with a map ignores the key. New `--place`
  with no map globs. The rig fake reads only `sid`, `src` and `w`.

### F. Findings

**F1 (MED). G-B4.2 and §5 leave out an intra-pass window.** The index answers as of each store's
refresh, which happens at that store's first lookup in the pass (`_store` → `_refresh`,
`transcript.py:251-260`, `:211-249`). The glob it replaces answers at `--place` time.

- M, `python3 -I /tmp/b4rev/r1sim.py`: the real `ProjectsIndex`, the design's `with_holds` body,
  3 stores, `roll_passes=10`.
  - A same-slug copy created **after** the pass's refresh and before `with_holds` gives
    `map b:False` against `glob b:True` in that pass, and `True` on the next pass.
  - B2's async lane widens the gap by up to the age of the answer (`B2:489-490`).
- **Consequence for a same-slug copy:** the arrival refusal fires. See F2: one wasted attempt and
  one rail token, not a strand.
- Who could write that copy mid-pass is only a second mover of the same sid (H).

**F2 (MED). §5 row 4 misnames the outcome ("NOTMOVED", "One attempt").** Here is what actually
happens:

1. `lr-transplant` exits 2. `lr-handoff` prints `verdict: FAILED` (`:1689`). That verdict is not
   `HELD|REFUSED`, so `_REASON` (`settle.py:61`) does not match it.
2. `classify` matches no allowlist, so the class is DETERMINISTIC (`classify.py:118-126`).
3. `apply_failure` returns RETRY (`:198-199`). `_score` adds one to `attempt` and sets the substate
   to BACKOFF (`settle.py:278`, `:308-313`).
4. `movers()` re-offers a BACKOFF record (`plan.py:255-266`).

It stays at one attempt **only if the next map says `True`**. A second identical refusal is
ESCALATED, which means at least a 15-minute re-arm, capped at 4 re-arms (`classify.py:194-197`,
`:23-26`).

- The map does turn `True` on the next pass, and it does so **without** the census:
  - `with_holds` asks the source store too;
  - `find` then touches the source transcript's dir name (`transcript.py:290-293`);
  - touched names apply in every store on the next refresh (`:240`).
- Verified in r1sim with no observe call, passes 2 and 4.
- One gap: an abstained pass returns before `_plan` (`__main__.py:1683` vs `:1715`). That pass
  touches nothing for a mover the census does not see, so for one pass such a mover falls back
  to the rolling slice.

**F3 (LOW-MED). C3's "same rows" holds only if the log is in time order, and the doc presents it
as unconditional.**

- **A demonstrated case.** M, `python3 -I /tmp/b4rev/c3adv.py <orig> <proto2>`: one write
  inversion straddling the cutoff (B at cutoff+30 s is written before A at cutoff-30 s), with the
  seed slice split between the two rows. Result: `orig keeps B: True 575`, `new keeps B: False
  574`.
- **How likely that is.** Order holds by construction in practice:
  - the only writer runs under `get_data`'s single-flight `flock` and stamps `ts` inside it
    (`:8319`, `:7124`, `_acquire_lock` `:8125-8147`; the efficacy review agrees);
  - exceptions are a wall-clock step backwards, or a writer whose lock file differs (H).
- **A second difference.** Today the main loop almost always falls through into the sibling
  branch, which sorts `out` (`:4745`). C3 skips that branch once `reached` is set, so on the
  reached path rows come back in **file** order. They are identical only when the file is
  ordered.
- **A cheap fix, measured.** `/tmp/b4rev/proto3`, built from proto2 with two changes:
  `crossed = crossed or t < cutoff - 3600` and an unconditional `out.sort`.
  - The adversarial case: `new keeps B: True 575`.
  - The live copy: kept rows and `json.loads` counts are identical to proto2's for every span
    above.

**F4 (LOW). With the same-slug outcome bounded (F2), the different-slug residual is the one way
B4 can still strand a session.**

- A copy under a different slug passes the arrival check. The next hop then fails with "multiple
  copies … disambiguate manually" (`lr-transplant.sh:869-875`).
- That failure is DETERMINISTIC, then ESCALATED, then re-armed four times, then released
  (`classify.py:23-26`). In other words, a session that is stuck until an operator acts.
- It is rare (M by the designer: 0 of 24 multi-store sids use different slugs). But "only a second
  driver writes it" (§5 row 3) is a hypothesis and should be labelled H.
- Same point as the efficacy review's F9. An independent mitigation on the actuator side: widen
  admit's arrival refusal to `$TO/projects/*/$SID.jsonl`. That is one glob per move, off the
  scorer, and it turns the strand into a re-place.

**F5 (LOW). The map is keyed by account name, but `with_holds` and `--place` can resolve that
name from different files.**

- `with_holds` resolves the store from `_amap(ctx.home)`, which reads
  `<HOME>/.claude/accounts.json` and ignores `CLAUDE_ACCOUNTS_JSON` (`__main__.py:152-163`).
- `--place` reads `CLAUDE_ACCOUNTS_JSON` first (`bin/claude-accounts:245`).
- `plan.kmax()` already uses `--place`'s order (`plan.py:171-186`) for this reason.
- A name-keyed bool computed over a different `config_dir` would be trusted. M: the live plists
  do not set it (`grep -c CLAUDE_ACCOUNTS_JSON ~/Library/LaunchAgents/*recon*.plist` gives 0 in
  each of the 4), so this is latent.

**F6 (LOW). Two tests cannot do what they claim.**

- **E1.** M, `python3 -I /tmp/b4rev/e1bound.py /tmp/b4/proto2/claude-accounts` gives
  `json.loads=11880` for 49 h on 40,000 lines over 20 days. That is above the 5,000 bound. This
  confirms the efficacy review's F1 with an independent fixture.
- **U2.** The old rule stops after the first sibling whenever a kept row falls within 60 s after
  the cutoff (`:4743`). U2 sets no cutoff offset, so it can pass before the fix too, and then it
  is not a red proof.

**F7 (LOW). The design never runs R1 end to end.** No test drives `run_pass` → `_plan` →
`plan.place` with a real index. R7 calls `_plan` the way `test_main.py:1679` does, outside any
`pass_index`, so it would read `holds=0/n` and still pass on the `holds=` token.

### Required changes

1. **G-B4.2 and §5: state the intra-pass window (F1).**
   - Say that the map answers as of each store's refresh in the pass, not as of `--place`, and
     that B2's async lane adds the answer's age to that gap.
   - Add **R4b**: a same-slug copy created after the refresh in the same pass reads `False`, and
     reads `True` on the next pass.
   - Optional hardening: the reconciler also sends the source transcript's dir name (`slug`).
     `--place` then calls `lexists(<cfg>/projects/<slug>/<sid>.jsonl)` for every account the map
     marks `False`. That is one `lstat` per account, and it closes the same-slug window at
     `--place` time.
2. **§5 row 4 (F2).**
   - Replace "NOTMOVED / One attempt" with the real chain:
     `verdict: FAILED` → DETERMINISTIC → RETRY, `attempt+1`, BACKOFF → re-placed. A second
     identical refusal is ESCALATED.
   - Run R4's same-slug case **without** any observe or `find_transcript` call, so it pins the
     touch that `with_holds` gets from asking the source store.
   - State the one-pass lapse after an abstained pass.
3. **C3 and G-B4.4 (F3).**
   - State the order precondition and cite `:8319`, `:7124` and `:8125-8147`.
   - Then either add `UTIL_TAIL_CROSS_SLACK_S`, so the read counts as "reached" only past
     `cutoff - slack` (measured: free on the live log), or keep the claim conditional and name
     its exceptions.
   - Either way, make `out.sort(key=_t)` unconditional, so the row order no longer depends on the
     path taken.
   - Add **U5**: one inversion straddling the cutoff, with the seed slice split between the pair.
     The rows must equal the old rule's. U5 is red on proto2 (M, `c3adv.py`).
4. **E1 and U2 (F6).**
   - E1: replace the absolute bound with a scaling assertion. Use two series with identical last
     49 h, 20 days and 60 days long, and require equal utilization `json.loads` counts.
     Alternatively, bound the count relative to the rows kept.
   - U2: offset the fixture so that no row lands within 60 s after the cutoff, and set the
     sibling mtimes with `os.utime`.
5. **An R1 integration test (F7).** Use a tmp `accounts.json` over `Tree`-style stores, the real
   `ProjectsIndex` and a spied `plan.place`.
   - Through `run_pass`, every mover passed to `place` carries `holds` equal to `old_glob`, and
     the event reads `holds=n/n`.
   - With an unreadable `accounts.json`, the movers file has no `holds` key.
   - `with_holds` called off the index's thread returns movers with `holds is None` and raises
     nothing.
6. **SSOT (F5).** `with_holds` resolves account → `config_dir` exactly as `--place` does
   (`CLAUDE_ACCOUNTS_JSON`, else `~/.claude/accounts.json`, as `plan.kmax`).
   - Or ship `{acct: [cfg, bool]}` and have `--place` trust an entry only when
     `realpath(cfg) == realpath(dirs[a])`.
7. **§12.1 (F4).** Call the different-slug consequence a strand that needs manual
   disambiguation, label "second driver" H, and record the actuator-side widening as the
   follow-up that would remove it.

### Not required

- **B3's kept target.** B3's kept-target path skips `--place`'s `store-holds-sid` (B3 F-G). Once
  R1 lands, `m.holds[rec.target_acct]` answers that check for free on the same pass, so B3 can
  fall back to `--place` when it reads `True`.
