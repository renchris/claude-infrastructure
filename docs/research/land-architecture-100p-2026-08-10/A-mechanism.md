# A — Landing path mechanism, as the code ships it (2026-08-10)

Subject: `claude-infrastructure` `/ship` → `scripts/ship-land.sh` + `scripts/land-lock.sh`.
Every cite is `file:line` at trunk `d52c3a94`. **[M]** = measured this session. **[L]** = from
`~/.claude/land.log` (2,929 rows, 2026-07-11 → 2026-08-10). **[T]** = reasoning from the code, not
measured.

---

## 0. Headline findings (the four that change an architecture decision)

1. **The mutex is NOT the correctness boundary, and it does not provide mutual exclusion in the one
   case it exists for.** The dead-holder reap in `land-lock.sh:120-123` is `rm -rf` + `mkdir` —
   non-atomic. **[M]** 6 concurrent acquirers against one stale/dead lock produced **3 simultaneous
   holders** (starts `…011.764174`, `…011.764187`, `…011.770785` — 13 ms apart, each holding a 2 s
   critical section). What actually prevents the 2026-07-11 drop class is the **CAS**
   (`ship-land.sh:2101-2109`) + **content-verify** (`land-verify.sh`) + bounded retry — all of which
   work whether or not the lock held.
2. **The lock hold is O(local branches), not O(diff), and it is growing.** `stranded-sweep.sh` runs
   **inside** the mutex (`ship-land.sh:2228`) and measured **59.2 / 59.2 / 62.7 s** over **497
   branches** **[M]**. `land.log` `hold_s` p50 by day: 31 s (08-05) → 32 (08-06) → 50 (08-07) → 46
   (08-08) → 57 (08-09) → **69 (08-10)** **[L]**. The only event that ever *reduced* it was a
   branch-count GC (`ship-backup-reap.sh`, `9ff61fa7`, 2026-07-30 → p50 107 → 37 on 08-02). Both
   published figures are stale: `README.md:230` says "held 5-15s"; `.claude/commands/ship.md:108`
   says "84-302s".
3. **83 % of lands execute no test of their own diff, and the net behind them is 55.7 h stale.**
   Of 530 attested lands in 7 d: `smoke` = `none` 258, `skipped` 181, `partial` 37, `green` 33,
   `red` 21 — only **91/530 (17 %)** earned any behavioural verdict **[L]**. The post-land verifier
   that v2's correctness argument defers to has a newest GREEN stamp **55.7 h old** **[M]** (its own
   staleness ceiling is 24 h, `ship-land.sh:535`), hence `net:"inert"` on 312/530 lands, `live` on
   82 **[L]**. Live layer is **323 commits** behind `last-green` **[M]**.
4. **`exit 127` in `land.log` is not a landing failure — it is an agent typo that took the real
   machine-wide mutex.** `land-lock.sh` recognises exactly two arguments (`--print-lock-dir`:56,
   `--`:68); **everything else is executed as the wrapped command**. Recovered from the session
   transcript: `bash scripts/land-lock.sh --status`
   (`…/wt-42c2a4879281/16c12522-ad53-4e22-b35a-7c9f4d458ef5.jsonl`, 2026-08-08T17:57:05Z). **[M]**
   reproduced in an isolated lock dir: acquires the lock, prints `line 155: --status: command not
   found`, exits 127, appends a row. 10 rows in 7 d, 24 all-time **[L]**.

---

## 1. Phase map — FAST lane (default), CAS mode

`IN` = executes while the land-lock is held. Costs are wall-clock on this box **[M]** unless marked.

### 1a. Preflight — `main_outer`, entirely OUTSIDE the lock

| # | Phase | file:line | Lock | Typical cost | Refusal |
|---|---|---|---|---|---|
| P0 | arg parse (`--dry-run`/`--trunk`), `detect_trunk` | `ship-land.sh:2264-2274`, `505-510` | out | <0.1 s | exit 2 on unknown arg |
| P1 | shared-checkout refusal (protected / non-session branch) | `2280-2294` | out | ~0 | **exit 4** |
| P2 | dirty-tree refusal (`git status --porcelain`) | `2296-2301` | out | ~0 | **exit 2** |
| P3 | preflight `git fetch` + `FIRST_BASE` anchor + `merge-base` + nothing-to-land | `2303-2317` | out | 0.43 s network **[M]** | exit 2 / exit 0 |
| P4 | escalation scan — 2 classes (DISCLOSURE never-exemptible; EFFECT exemptible via `scripts/esc-exempt.manifest` read at the range's **base** rev) | `2319-2329`; `esc_scan:361`, `esc_exempt_patterns:328`, `write_decision_packet:429` | out | O(diff), ~1 s | **exit 3** + decision packet, attested |
| P5 | P6 gate-batching backstop (`gate-manifest.sh backstop`) — non-blocking by contract | `2331-2335` | out | ~0.1 s | never changes exit |
| P6 | safety ref `ship/backup-<sha>`, **exported** to the locked child | `2337-2346` | out | ~0 | — |
| P7 | optimistic-round loop, `SHIP_LAND_GATE_ROUNDS` default **3** | `2352-2368` | out | — | — |

### 1b. Per optimistic round — `unlocked_reconcile_and_gate`, OUTSIDE the lock

| # | Phase | file:line | Lock | Typical cost |
|---|---|---|---|---|
| R1 | `git fetch origin <trunk>` (failure = warn, proceed) | `2035` | out | 0.4 s |
| R2 | `git rebase origin/<trunk>` — conflict ⇒ **exit 5**, rebase LEFT IN PROGRESS (deliberate: a human ran `/ship`) | `2037-2040` | out | 0.2-3 s |
| R3 | `GATE_BASE` pin + nothing-to-land ⇒ exit 0 | `2042-2048` | out | ~0 |
| R4 | **`run_gate`** — see §1c | `2050`, body `1276-2013` | out | **5-180 s** |
| R5 | `stamp_gate_green` — **self-noop in v2** (`GATE_EFFECTIVE_FULL=0` always, `193`) | `2064`, `1260` | out | ~0 |
| R6 | `--dry-run` stop (never takes the lock — asserted `tests/land-gate-cas.bats:271-282`) | `2066-2071` | out | exit 0 |
| R7 | `GATE_HEAD` pin | `2073` | out | ~0 |
| R8 | export gate facts to the child (`SMOKE_STATE/_N/_S`, `NET_STATE`, `SELECTED_N`, `FIRST_BASE`) | `2358-2363` | out | ~0 |
| R9 | spawn `land-lock.sh -- $SELF __locked <trunk> <dry> <base> <head>` | `2364` | — | — |
| R10 | rc 42 ⇒ re-round (union scope `FIRST_BASE..new base` handed to the selector) | `2365-2367`, `196-200` | out | full R1-R9 again |

### 1c. `run_gate` (unlocked) — what the "fast" gate actually is

15 arms, in fire order. **Blocking scope is narrowed to own-diff files via `CC_*_OWN`, but the SCAN
is repo-wide** — the ratchets are invoked as `"$LINT" tests` or with no args at all
(`1360, 1400, 1429, 1472, 1521, …`), i.e. **O(repo), not O(diff)**, contradicting the file header's
"a LAND carries only work that is O(diff)" (`ship-land.sh:13`).

| Arm | file:line | Cost **[M]** (full-repo invocation) |
|---|---|---|
| changed-file collection (deletions skipped — the `deleted-*.sh` red) | `1284-1294` | O(diff) |
| `shellcheck` + `bash -n` on changed shell files | `1296-1302` | 0.5-5 s |
| `python3 -m py_compile` (incl. extensionless-by-shebang) | `1304-1307` | 0.3-2 s |
| test-hermeticity ratchet (`test-hermeticity-lint.sh tests`) | `1334-1391` | **32.6 s** |
| wall-clock time-bomb ratchet | `1394-1420` | **5.8 s** |
| AF_UNIX absolute-bind ratchet | `1423-1456` | ~5 s [T] |
| git-identity escape ratchet | `1459-1504` | **12.3 s** |
| UTC timestamp-contract ratchet (+ `--selftest` first) | `1507-1553` | **5.0 s** |
| pipefail/SIGPIPE ratchet | `1556-1624` | ~5 s [T] |
| /Users/chrisren/.claude/bin/cc-bats dead-assertion ratchet | `1627-1673` | O(changed suites) |
| script-dir resolution ratchet | `1676-1712` | ~2 s [T] |
| pane-spawn coverage ratchet | `1715-1768` | ~2 s [T] |
| bare-name binaries on unattended paths | `1771-1822` | ~2 s [T] |
| unbounded permission gates | `1825-1863` | **0.14 s** |
| chromium-bundle ratchet | `1866-1915` | ~1 s [T] |
| `.bats` shellcheck ratchet | `1918-1955` | O(changed suites) |
| unguarded-kill ratchet | `1958-2000` | **4.4 s** |
| **smoke** → `run_smoke` | `2004`, body `961-1065` | ≤`SHIP_LAND_SMOKE_BUDGET_S` (120 s); **p50 120 s, p90 279 s, max 1200 s when it runs** **[L]** |

Smoke rules (`961-1065`): the `--direct` suites of this diff **minus** host suites
(`filter_host_suites:920`, `scripts/host-suites.manifest`); one process per suite under ONE total
budget; `nice`d; each child bounded by an absolute-path `timeout -k 10` (`_resolve_timeout:259`).
RED ⇒ `gate_red smoke:<file>` ⇒ exit 6. CUT/budget ⇒ `smoke:"partial"`, **land proceeds**. Load ≥
ceiling ⇒ **skipped entirely** (`1011-1020`); ceiling is derived `hw.ncpu ×
CC_GATE_MAX_LOAD_PER_CORE(8)` = 80 here (`608-668`), raised from the constant 8 on 2026-08-08.

> **`smoke:"none"` collapses five distinct causes into one token** — no `tests/*.bats` (`976`),
> `IN_LAND_LOCK=1` (`981-984`), selector missing/not executable (`986-993`), selector answered
> `FULL` (`995-1000`), 0 direct suites after host filtering (`1006-1009`). 258 of 530 lands attest
> `none` **[L]**, and a reader cannot tell "nothing to smoke" from "the selector was missing because
> of the new-file symlink deploy gap" — the exact failure the same file documents at `130-141`.

### 1d. INSIDE the lock — `main_locked`, CAS mode (`GATE_BASE`/`GATE_HEAD` non-empty)

**Everything in this table holds the machine-wide mutex.**

| # | Phase | file:line | Cost | Exit |
|---|---|---|---|---|
| L0 | acquire (poll 2 s, no FIFO) | `land-lock.sh:127-139` | `wait_s` p50 **0**, p99 50, max 70 (7 d) **[L]** | 75 on `LAND_LOCK_WAIT` |
| L1 | `IN_LAND_LOCK=1` — structural "no /Users/chrisren/.claude/bin/cc-bats in the lock" | `ship-land.sh:2081`; enforced `981-984` + `1993-1998` | ~0 | — |
| L2 | last-moment `git fetch origin <trunk>` — **network, unbounded** | `2097-2098` | 0.4 s nominal | — |
| L3 | **CAS**: `origin/<trunk>` still `GATE_BASE` **and** `HEAD` still `GATE_HEAD`? | `2101-2109` | ~0 | **42** (internal) |
| L4 | `attest_refs` + `git push origin HEAD:<trunk>` — **network, unbounded, no timeout** | `2152-2157` | 0.5-3 s | **7** |
| L5 | `git fetch` + `land-verify.sh <base>..<head> origin/<trunk> <head>` — per path: 2× `ls-tree` + 1× `diff` | `2159-2163`, `land-verify.sh:52-74` | O(paths) forks | — |
| L6 | content-drop retry loop, ≤`SHIP_LAND_VERIFY_RETRIES` (2): fetch → rebase → **`run_gate` (2nd in-lock gate call site)** → push | `2159-2205` (gate at `2189`) | +~60 s of ratchets **inside** the lock per retry [T] | **8** exhausted · **5** retry-rebase conflict (rolled back) · **0** self-heal |
| L7 | `ship-backup-reap.sh reap <ref> <landed-head>` — the ONLY place the backup ref may die | `2207-2225` | ~0.2 s | never fails the land (`\|\| true`) |
| L8 | **`stranded-sweep.sh <trunk>`** — walks EVERY local branch, `git cherry` + per-path `ls-tree` | `2227-2236`, `stranded-sweep.sh:66-116` | **59.2 / 59.2 / 62.7 s over 497 branches** **[M]**; rc 1 = REVIEW (normal — 59 stranded commits today) | never blocks |
| L9 | `attest_land ok <sweep> clean 0` | `2238`, `476-496` | ~0 | — |
| L10 | queue landed head + detached `postland-verify.sh --run-if-needed` (`start_new_session`) | `2240-2255` | ~0.1 s | never fails the land |
| L11 | release (EXIT trap) + `logline wait_s hold_s exit` | `land-lock.sh:141-148` | — | — |

**Measured hold** (`exit 0`, 7 d, n=344): min 25 · p50 **46** · p90 68 · p99 152 · max 273 s **[L]**.
All-time p50 62 · p90 233 · p99 1787 · max **6771 s** (2026-07-25, v1 era) **[L]**.

**In-lock budget attribution** [T over [M] parts]: sweep ~60 s + push/fetch ~1-4 s + verify O(paths)
≈ the whole p50. **The lock is ~90 % stranded-sweep, and the sweep is an advisory report** whose own
contract is "REVIEW, never an automatic failure and never an auto-recover"
(`stranded-sweep.sh:16-18`).

### 1e. Fallback mode — rounds exhausted or `SHIP_LAND_GATE_ROUNDS=0`

`ship-land.sh:2370-2376` → `exec land-lock.sh -- $SELF __locked <trunk> <dry> "" ""`.

| # | Phase | file:line | Lock | Note |
|---|---|---|---|---|
| F1 | `git rebase origin/<trunk>` **inside the lock** | `2111-2114` | IN | exit 5 (left in progress) |
| F2 | nothing-to-land | `2117-2120` | IN | exit 0 |
| F3 | **`run_gate` inside the lock** — statics + ratchets only; `run_smoke` returns at `981-984`, v1 corpus refused at `1993-1998` | `2122-2127` | IN | exit 6/9; ~60 s of ratchets **inside the mutex** **[M/T]** |
| F4+ | then L4-L11 as above | | IN | |

Empirically the fallback fires: **34 all-time `exit 6` rows carry `wait_s`** (the land-lock schema),
i.e. in-lock gate reds — invisible in the `ship-land` schema because `2122-2125` exits **without**
`attest_land` **[L]**.

---

## 2. Exit codes — complete table

`ship-land.sh` (`75-88` documents them; this table is from the call sites):

| Code | Meaning | Raised at | Attested to land.log? | 7 d / all-time **[L]** |
|---|---|---|---|---|
| 0 | landed (or nothing-to-land, or dry-run, or drop self-healed) | `2047, 2070, 2118, 2133, 2187, 2258, 2316` | yes for `2187`/`2238`; **no** for nothing-to-land / dry-run | 344 / 1002 |
| 2 | preflight refusal — dirty tree · bad arg · unknown LANE/SCOPE · no merge-base | `2271, 2300, 2311, 168, 185` | **no** | 0 / 0 |
| 3 | escalation PARK (decision packet written; never auto-landed) | `2328` | yes | 0 / 12 |
| 4 | shared-checkout refusal | `2287, 2292` | **no** | 0 / 0 |
| 5 | rebase conflict — initial (left in progress) or auto-retry (rolled back) | `2039, 2113, 2180` | only `2180` | 0 / 10 (lock schema) |
| 6 | **GATE RED — a verdict about your diff** | `gate_nonzero_code:2014-2026` at `2057, 2124, 2193` | yes at `2057`/`2193`, **no** at `2124` | 186 / 456 |
| 7 | push rejected non-ff (a non-pipeline pusher beat you) | `2156` | **no** | 1 / 1 |
| 8 | content-verify failed after exhausting retries; tree clean, backup ref intact | `2170` | yes (`"verify":"FAIL"`) | 0 / 0 |
| 9 | **GATE-KILLED — a non-verdict about the machine** (retry IS correct) | `gate_nonzero_code` when `GATE_KILLED=1 && GATE_RED=0` | yes | 0 / 0 |
| 42 | **INTERNAL stale-gate signal**; never escapes `ship-land` (`2366` swallows it) | `2107` | **no** (only the lock line records it) | 79 / 306 |

`land-lock.sh`:

| Code | Meaning | Raised at | 7 d / all-time |
|---|---|---|---|
| 64 | no command given (`EX_USAGE`) | `land-lock.sh:69` | 0 / 0 |
| 75 | `EX_TEMPFAIL` — waited the whole `LAND_LOCK_WAIT` (3600 s) without acquiring | `131-134` | 0 / **19** |
| 127 | **wrapped command not found** — includes any unrecognised flag (§0.4) | pass-through of `"$@"` at `155-157` | 10 / 24 |
| 130 | the trap's *initialiser* — the wrapper died before `CODE=$?` ran (SIGINT/SIGTERM during the hold) | `142` + trap `144-148` | 3 / 16 |
| 143 | SIGTERM propagated from the child | pass-through | 0 / 2 |
| *n* | anything the child returns | `155-157` | — |

**6 vs 9** (`ship-land.sh:81-87`, `commands/ship.md:109`): 6 = the gate ran and named a failing
test/file ⇒ a claim about *your code*, do not retry unchanged. 9 = the run died to a signal or exited
naming zero failing tests ⇒ a claim about *the machine*, retry is correct. Both fail-closed. 9 is now
**structurally unreachable in the fast lane** — the smoke never escalates a cut (`961-972`,
`1057-1061`), so only `SHIP_LAND_LANE=v1`'s corpus can earn it. **[L]** confirms: 0 ever.

**Attestation gaps (they make `land.log` an unreliable denominator).** Exits 2, 4, 7, 42, the initial
rebase-5, the in-lock fallback gate-6 (`2124`), and every nothing-to-land/dry-run 0 write **no**
`ship-land` line. And `land.log` interleaves **two schemas** — 7-key lock telemetry
`{ts,repo,branch,wait_s,hold_s,exit,pid}` and the 18-19-key ship-land attestation
`{…,tool,verify,sweep,esc_scan,head,base,tree,gate_scope,selected_n,smoke,smoke_n,smoke_s,net,red}`
— so a naive `exit` histogram double-counts successes (344 + 344 in 7 d) and reads 10 typo-127s as
landing failures.

---

## 3. Lock lifecycle

**Key.** `git rev-parse --path-format=absolute --git-common-dir`, normalised by stripping
`/worktrees/*` then `/.git` (`land-lock.sh:43-49`) → `shasum | cut -c1-12` →
`/tmp/land-lock-<hash>/lock.d` (`50-52`; override `LAND_LOCK_DIR`). This is what makes all **125
worktrees** **[M]** of one repo collide on ONE mutex; `--show-toplevel` would have given each
worktree its own (G-P9-1). Introspection without landing: `--print-lock-dir` (`56-59`, exits before
any `mkdir` — a pure read).

**Acquire.** `mkdir "${LOCK}"` is the atomic primitive (`96`); on success `write_owner` records
`pid`, `lstart` (from `ps -o lstart=`), `branch` (`84-90`).

**Holder liveness / staleness** (`try_acquire:95-125`):

| Observed | Decision | Line |
|---|---|---|
| `pid` file empty (mkdir'd, owner mid-write) | grace 5 s, else `TTL` (1200 s) ⇒ stale | `101-103` |
| `kill -0` ok **and** recorded `lstart` == current `lstart` | **NEVER stale — not even past TTL** | `112-116` |
| `kill -0` ok but `lstart` differs | pid RECYCLED ⇒ original holder dead ⇒ reap | `112-113` |
| `kill -0` fails | dead ⇒ reap immediately | `117-119` |

The never-reap-a-live-holder rule is deliberate and diverges from reso (`92-94`): "a silently-dropped
commit costs more than a wedged-lock wait." **Consequence: there is no recovery at all for a LIVE but
hung holder** — a stalled `git push` (no timeout anywhere in the locked phase) blocks the whole box
until that process dies. The documented escape is `LAND_SERIALIZE=off` (`26, 79-82`), which
`commands/ship.md:108` says to **never** use.

**Waiters.** Poll every 2 s, progress line every 30 s (`129-138`). **No FIFO fairness** — every waiter
races `mkdir`, so starvation is possible in principle. Give up at `LAND_LOCK_WAIT` (3600 s) ⇒ **exit
75**, logged with `hold_s 0` (`131-135`). **[L]** 19 all-time; 82 rows waited ≥600 s, 22 waited
≥3600 s, max wait **7386 s** — all in the v1 era; 7-day `wait_s` p50/p90 are **0**.

**Crash recovery.** Normal exit → `trap release EXIT` removes the dir and logs (`144-148`). SIGKILL →
no trap → the dir survives with a dead pid → the *next* acquirer reaps it instantly. Reboot → `/tmp`
clears. There is no reaper daemon and no external unlock command; recovery is entirely
next-acquirer-driven.

**🚨 The reap is racy — reproduced.** `120-123` is `rm -rf "${LOCK}"` then `mkdir`. Two waiters that
independently conclude "stale" both delete (including a rival's *fresh* lock) and both create.
**[M]** 6 concurrent acquirers against one dead-pid lock, isolated `LAND_LOCK_DIR`/`LAND_LOG`:

```
IN-3 1786351011.764174   IN-6 1786351011.764187   IN-4 1786351011.770785   <- 3 holders, 13 ms apart
IN-1 1786351013.793026                                                     <- serialized (2 s later)
IN-2 1786351015.890464   IN-5 1786351015.912698                            <- 2 holders
```

`tests/land-lock.bats` has 11 tests covering live/dead/recycled/empty-pid/keying — **none covers
concurrent reap**. Exposure is proportional to queue depth *at the moment a holder dies*, so it was
large in the v1 era (82 waits ≥600 s) and is small today (p90 wait 0). It is survivable only because
the CAS + content-verify + bounded retry sit *behind* the lock.

**Telemetry.** `wait_s` = `now - WAIT_START` at acquisition (`127-139`); `hold_s` = `now - HOLD_START`
inside the EXIT trap (`141-146`); one JSON line to `${LAND_LOG:-~/.claude/land.log}` via `logline`
(`73-76`). Written by the **wrapper**, so it is the only honest hold measurement —
`tests/land-gate-cas.bats:283-295` asserts `hold_s ≤ 2` for a 3 s gate. **That test's fixture repo
has ~2 branches, so it is structurally blind to the 60 s sweep that dominates the real hold** — a
control calibrated to a fixture rather than to the mechanism.

---

## 4. Lane selection & escalation

**Lane** (`ship-land.sh:160-169`): `SHIP_LAND_LANE` ∈ {`fast` (default), `v1`}; anything else ⇒ exit
2. `fast` = statics + ratchets + bounded smoke, no corpus. `v1` = the pre-inversion full-corpus gate
(`run_corpus:878`, invoked `1993-2002`) — a one-release kill switch, still bound by the
never-in-lock invariant (`1993-1998`). **[L]** 530/530 lands in 7 d attest `gate_scope:"fast"`; `v1`
has never run in the logged window.

**Scope** (`171-186`): `SHIP_LAND_GATE_SCOPE` ∈ {full, scoped, shadow}, sourced from
`scripts/gate-policy.sh`, validated, and **deliberately inert** — neither lane consults it. Kept only
so an existing env/policy file cannot hard-exit a land.

**Escalation** (`esc_scan:361`, called `2320`): two classes with different scopes — DISCLOSURE
(`the PEM private-key header marker`, `294`) scans every changed file and is **never exemptible**; EFFECT
(destructive SQL, `293`) is exemptible per path by `scripts/esc-exempt.manifest` **read at the range's
base revision** (`328`), so an exemption added inside a range is inert for the land that adds it. A
hit writes a class-B decision packet under `~/.claude/autonomy/decisions/` and exits 3. **[L]** 12
parks all-time, 0 in the last 7 d; the manifest records the pre-split single-regex scan's measured
precision as **zero** (506 clean / 11 hit / 9 packets, every one benign).

**Landing-range escalation ≠ lock escalation.** There is no lane or route change on contention. The
only contention response is the round loop (3 optimistic rounds, then the in-lock statics fallback).
Re-round rate **[L]**: 306 exit-42 vs 1058 lands all-time ≈ **22 %** (79/344 ≈ **23 %** in 7 d) —
close to the ~30 % the header cites — and each re-round costs a full unlocked gate (~60 s of
repo-wide ratchets + up to 120 s smoke), **not** the "seconds" the header claims (`ship-land.sh:44-50`).

---

## 5. Adversarial pass — what I checked because a hostile reviewer would

| Challenge | Verdict |
|---|---|
| "You assert the sweep is in the lock — prove it isn't skipped or cheap." | `2228` sits inside `main_locked`, which *is* the wrapped command; no guard, no `-x` check, no timeout, no kill switch. Timed 3×: 59.2 / 59.2 / 62.7 s. **Confirmed.** |
| "hold_s p50 46 s < your 60 s sweep — the attribution is wrong." | Branch count grows monotonically; the daily p50 series runs 31 s (08-05) → 69 s (08-10) tracking that growth, and the one *fall* (107 → 37 on 08-02) follows `9ff61fa7`, which deletes `ship/backup-*` refs. The 7-day p50 averages over a smaller branch set than today's 497. **Attribution stands — and that it is a moving target IS the finding.** |
| "127 could be a real ship-land failure you mislabelled." | Recovered the literal command from the transcript (`bash scripts/land-lock.sh --status`) and reproduced the exact stderr + rc + log row in an isolated lock dir. Every 127 row has `wait_s=0, hold_s=0`, and the same branch lands cleanly minutes later. **Diagnostic artifact, not a landing failure.** |
| "Maybe the lock race is theoretical." | Ran it. 3 simultaneous holders out of 6. **Empirical.** |
| "Maybe `postland-verify` is fine and `net:inert` is a sensor bug." | Read the stamps dir directly: newest green stamp 55.7 h old; `launchctl` shows the agent loaded with `StartInterval 300`; `deploy-live.sh:21-25` independently documents the producer at **0.17 greens/day vs ~63 commits/day**; live layer 323 commits behind `last-green`. **The net really is inert.** |
| "Is `exit 42` a failure the operator sees?" | No — `2366` propagates only `rc ≠ 42`; the loop re-rounds. It reaches `land.log` **only** via the lock schema, which is why 79 rows look like failures to a naive reader. |
| "Does anything bound the locked phase?" | **No.** `_resolve_timeout` bounds only smoke children (`259-274`), and smoke cannot run in the lock. Both in-lock `git fetch`es and the `git push` are unbounded network calls; the sweep is an unbounded local walk. The only bound on a holder is its own termination. |

**Alternatives considered and ruled out**

- *"The 42s are contention and the lock is the bottleneck."* Ruled out: `wait_s` p50/p90 = 0 over 7 d.
  The 42 rows are the *waiters* (their `wait_s` p90 = 45), so the stale-gate signal is a symptom of a
  **long hold**, not of demand. Cut the hold and the 23 % re-round rate falls with it.
- *"The gate is the cost."* Partly — the gate is unlocked, so it costs latency, not throughput. The
  throughput term is entirely the in-lock sweep.
- *"exit 6 (186 in 7 d, 35 % of attested lands) means the tree is broken."* The `red` field says
  otherwise: `shellcheck` 17, `dead-assertion` 11, `shellcheck,dead-assertion` 7, `bats-shellcheck` 5,
  `hermeticity` 5 — mostly **repo-wide ratchets firing on files the land did not touch** — plus 121
  rows where `red` is empty because that exit-6 path does not populate it.

---

## 6. Blockers / uncertainties (named)

- **[T]** The per-arm ratchet costs marked `[T]` (afunix, pipefail, script-dir, pane-spawn, bare-name,
  chromium) were not individually timed; the six that were sum to **60.2 s**, so the full-arm figure
  is a lower bound.
- **[T]** In-lock retry cost (L6) is inferred from `run_gate` at `2189` plus the measured ratchet cost;
  no production instance exists (0 exit-8 ever), so that path has never been exercised at scale.
- **Unknown:** whether the 3-holder reap race has ever produced a real double-land. It would present
  as an exit-42 or a verify-retry, both indistinguishable in `land.log` from ordinary contention.
  Nothing records "I reaped a dead holder".
- **Unknown:** why `hold_s` p50 fell 107 → 37 on 2026-08-02 specifically; `9ff61fa7` (2026-07-30) is
  the best-fit cause, but the two-day gap is unexplained.
- `~/.claude/land.log` is **unrotated, 2 schemas, 2,929 rows** (`scripts/growth-coverage.conf:81`
  flags the rotation gap). Every quantitative claim above should be re-derived, never quoted later.
