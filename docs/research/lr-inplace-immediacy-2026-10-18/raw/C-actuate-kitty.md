# C: where the move lane's actuate stage spends its time, and why kitty is reported unreachable

Worker C, 2026-10-18. Read-only. No `kitty @`/`kitten @`, `cc-lr` or `lr-*.sh` was run. Helper scripts live in
`/tmp/lri-c/` (`table2.py`, `segments.py`). Every number is labelled **[m]** (measured: the source
or command is named) or **[e]** (estimated: the method is named). All times are UTC. File:line refers to this worktree at
`2b9d938de`.

**Short answer.** The ~1476 s is **not** a kitty timeout chain. In 43e6eb4b's 1476.8 s actuate, the
kitty probe that failed took **3 s**. Every kitty call before it answered. The rest is serial non-kitty work on a box
at load 22–40 per core: a 306 s transplant admit, 284 s of handoff-fire start-up and pre-gates, a 163 s precheck and a
649 s stand-down after the hold. If every bounded kitty call on the path ran to its bound, the worst case up to this
hold is ≈435 s **[e]**. The "unreachable" verdict came from one unretried 3 s connect probe. Its non-zero rc covers
several unrelated causes. The same socket and the same kitty process (pid 44163) answered 3 min before and 47 s after.

---

## 1. Per-session table: every sid in every `move/2026101[78]T*` batch

**[m]** `python3 -I /tmp/lri-c/table2.py`, read at 2026-10-18T02:24–02:30Z. Batch `·N` is the batch-dir pid suffix.
Duration = `actuated.t_ms − actuate.t_ms` from `<sid>.events.jsonl`, and rc is the `actuated` detail. The tag is the last
`HELD:`/`REFUSED:` token in `<sid>.handoff.log`, which is the same extraction as `lr-move-worker.sh:174`. The reason is the
first `!!` line, or the PRECHECK/REFUSED line. The verdict comes from `<sid>.json`. `-` means the worker never reached W5.
Batches `020022Z` and `021322Z` were still running when read.

| batch | sid8 | actuate→actuated s | rc | tag | reason (handoff.log, trimmed) | final verdict (`<sid>.json`) |
|---|---|---|---|---|---|---|
| 20261017T073813Z·26358 | 1bf14662 | 4.8 | 6 | REFUSED:intent-invalid | REFUSED:intent-invalid — the intent expired 88s ago | NOTMOVED: REFUSED:intent-invalid (wall_s 622) |
| 20261017T073813Z·26358 | 30c3a88d | 512.4 | 6 | HELD:unreachable | !! recycle HELD (kitty is not answering): socket accepted a connection, but 'kitty @ ls' did not answer within 10s (1 queued) | NOTMOVED: HELD:unreachable (wall_s 554) |
| 20261017T073813Z·26358 | 76033be2 | 0.9 | 6 | REFUSED:intent-invalid | REFUSED:intent-invalid — the intent expired 48s ago | NOTMOVED: REFUSED:intent-invalid (wall_s 575) |
| 20261017T073813Z·26358 | 9f6593c5 | 893.0 | 0 | - | verdict=SWITCHED-UNPROVEN — pane 7 recycled onto 'next', /exit landed | STRANDED: no live process holds the session (resume debt: open) (wall_s 1353) |
| 20261017T073813Z·26358 | ab512c88 | 580.9 | 6 | HELD:unreachable | !! recycle ABORTED (resolver CANNOT TELL): pane→tty resolver never answered — 5 attempts, every one a FAILED query | NOTMOVED: HELD:unreachable (wall_s 630) |
| 20261017T073813Z·26358 | f7351f3b | 544.5 | 6 | HELD:unreachable | !! recycle ABORTED before /exit (held: unreachable): composer UNREADABLE (no box could be read) | NOTMOVED: HELD:unreachable (wall_s 580) |
| 20261017T235745Z·69993 | 6db28068 | - | - | - | - | NOTMOVED: still-busy:background-job after 3600s (wall_s 3603) |
| 20261017T235745Z·69995 | 756b68c8 | - | - | - | - | NOTMOVED: batch refused: another batch held the admit section for 90s (wall_s 0) |
| 20261017T235745Z·69998 | 7b50757e | - | - | - | - | NOTMOVED: batch refused: another batch held the admit section for 90s (wall_s 0) |
| 20261017T235745Z·70005 | 509e3aad | - | - | - | - | NOTMOVED: still-busy:background-job after 3600s (wall_s 3606) |
| 20261017T235746Z·69994 | 4736324c | - | - | - | - | NOTMOVED: still-busy:background-job after 3600s (wall_s 3601) |
| **20261018T000816Z·49288** | **43e6eb4b** | **1476.8** | 6 | **HELD:unreachable** | !! recycle HELD (kitty is not answering): the control socket /tmp/kitty-44163 did not accept a connection (0 queued). | NOTMOVED: HELD:unreachable — live in pane 8, one copy (wall_s 2167) |
| **20261018T000922Z·71757** | **7b50757e** | **1558.2** | 6 | **HELD:unreachable** | !! recycle ABORTED: the terminal did not answer the watcher's pane probe for 47 (a failed listing, typically the 10 s bound firing…) | NOTMOVED: HELD:unreachable — live in pane 47, one copy (wall_s 2161) |
| 20261018T002357Z·40187 | e739e5b5 | 1910.5 | 6 | REFUSED:not-limited | PRECHECK REFUSED:not-limited — nothing transplanted (intent expired 1106s ago) | NOTMOVED: REFUSED:not-limited (wall_s 2931) |
| 20261018T002443Z·84451 | 756b68c8 | - | - | - | - | (no `<sid>.json`; stopped at `waiting`) |
| 20261018T003928Z·31080 | 381200c5 | - | - | - | - | NOTMOVED: claim-held: held-live pid 42086 (wall_s 0) |
| 20261018T004329Z·1739 | ab512c88 | - | - | - | - | NOTMOVED: still-busy:unread after 900s (wall_s 903) |
| 20261018T005330Z·69593 | 04b3cbc3 | - | - | - | - | NOTMOVED: still-busy:unread after 1800s (wall_s 1802) |
| 20261018T005330Z·69593 | 246a91b5 | 8.2 | 6 | REFUSED:intent-invalid | REFUSED:intent-invalid — the intent expired 902s ago | NOTMOVED: REFUSED:intent-invalid (wall_s 201) |
| 20261018T005330Z·69593 | 2e9ed9f2 | 5.0 | 6 | REFUSED:intent-invalid | REFUSED:intent-invalid — the intent expired 904s ago | NOTMOVED: REFUSED:intent-invalid (wall_s 175) |
| 20261018T005330Z·69593 | 381200c5 | - | - | - | - | NOTMOVED: still-busy:unread after 1800s (wall_s 1800) |
| 20261018T005330Z·69593 | 756b68c8 | - | - | - | - | NOTMOVED: claim-held: held-live pid 99147 (wall_s 0) |
| 20261018T005330Z·69593 | 8db0e6f1 | 4.8 | 6 | REFUSED:intent-invalid | REFUSED:intent-invalid — the intent expired 904s ago | NOTMOVED: REFUSED:intent-invalid (wall_s 184) |
| 20261018T005330Z·69593 | e3dedc17 | 5.1 | 6 | REFUSED:intent-invalid | REFUSED:intent-invalid — the intent expired 904s ago | NOTMOVED: REFUSED:intent-invalid (wall_s 185) |
| 20261018T012244Z·22836 | 04b3cbc3 | - | - | - | - | NOTMOVED: claim-held: held-live pid 38260 (wall_s 0) |
| 20261018T012244Z·22836 | 246a91b5 | - | - | - | - | NOTMOVED: claim-held: held-live pid 38052 (wall_s 0) |
| 20261018T012244Z·22836 | 2e9ed9f2 | - | - | - | - | NOTMOVED: claim-held: held-live pid 45965 (wall_s 0) |
| 20261018T012244Z·22836 | 381200c5 | - | - | - | - | NOTMOVED: claim-held: held-live pid 42086 (wall_s 0) |
| 20261018T012244Z·22836 | 43e6eb4b | 627.6 | 6 | HELD:load | !! recycle ABORTED before /exit (held: load): load 28.61/core is above the 8/core bound | NOTMOVED: HELD:load (wall_s 822) |
| 20261018T012244Z·22836 | 4736324c | - | - | - | - | (no `<sid>.json`; stopped at `waiting`) |
| 20261018T012244Z·22836 | 509e3aad | - | - | - | - | (no `<sid>.json`; stopped at `waiting`) |
| 20261018T012244Z·22836 | 6db28068 | - | - | - | - | (no `<sid>.json`; stopped at `waiting`) |
| 20261018T012244Z·22836 | 756b68c8 | - | - | - | - | NOTMOVED: claim-held: held-live pid 99147 (wall_s 0) |
| 20261018T012244Z·22836 | 7b50757e | 681.8 | 6 | HELD:load | !! recycle ABORTED before /exit (held: load): load 27.41/core is above the 8/core bound | NOTMOVED: HELD:load (wall_s 917) |
| 20261018T012244Z·22836 | 8db0e6f1 | - | - | - | - | NOTMOVED: claim-held: held-live pid 38577 (wall_s 0) |
| 20261018T012244Z·22836 | e3dedc17 | - | - | - | - | NOTMOVED: claim-held: held-live pid 45363 (wall_s 0) |
| 20261018T012244Z·22836 | e739e5b5 | 813.4 | 4 | - | !! recycle ABORTED before /exit (held: load): load 25.67/core | STRANDED: no live process holds the session (resume debt: none) (wall_s 1276) |
| 20261018T014908Z·23285 | 1bf14662 | 194.4 | 6 | HELD:draft | PRECHECK HELD:draft — nothing transplanted | NOTMOVED: HELD:draft (wall_s 307) |
| 20261018T014908Z·23285 | 30c3a88d | 709.0 | 1 | - | verdict=FAILED — lr-transplant exited 1 | NOTMOVED: HELD:unknown (lr-handoff rc 1) (wall_s 1054) |
| 20261018T014908Z·23285 | 76033be2 | - | - | - | - | NOTMOVED: slot-wait: no move slot freed in 600s (wall_s 621) |
| 20261018T014908Z·23285 | ab512c88 | - | - | - | - | NOTMOVED: claim-held: held-live pid 61594 (wall_s 0) |
| 20261018T020022Z·2123 | 246a91b5 | 1.4 | 2 | - | REFUSED — pane 1 does NOT hold session 246a91b5 (registry says 4fd71ecf) | STRANDED: no live process holds the session (resume debt: proven) (wall_s 390) |
| 20261018T020022Z·2123 | 2e9ed9f2 | 353.5 | 6 | HELD:load | !! recycle ABORTED before /exit (held: load): load 13.91/core | NOTMOVED: HELD:load (wall_s 778) |
| 20261018T020022Z·2123 | 8db0e6f1 | 534.0 | 4 | - | !! recycle ABORTED before /exit (held: load): load 13.14/core | STRANDED: no live process holds the session (resume debt: proven) (wall_s 939) |
| 20261018T020022Z·2123 | e3dedc17 | 494.2 | 6 | HELD:unknown | !! --recycle REFUSED: no session-registry row for pane 201 | STRANDED: no live process holds the session (resume debt: none) (wall_s 577) |
| 20261018T021322Z·22546 | 43e6eb4b | 370.6 | 6 | HELD:load | !! recycle ABORTED before /exit (held: load): load 13.43/core | NOTMOVED: HELD:load (wall_s 490) |
| 20261018T021322Z·22546 | 7b50757e | - | - | - | - | (no `<sid>.json` yet; in flight) |

Base rate **[m]** (`jq` over `~/.claude/logs/handoffs.jsonl`, 1184 rows, 2026-10-15T10:18Z → now). The up-front kitty
probe held a recycle 6 times. In 5 of them the socket accepted and `kitty @ ls` did not answer within 10 s, with the
probe taking 10–13 s. In 1 the connection was not accepted: 43e6eb4b at 00:30:54, with the probe taking ≈3 s.

---

## 2. Measured decomposition of the two ~25-minute actuates

Sources **[m]**:
- `<batch>/<sid>.events.jsonl`
- `~/.reso/limit-recover/<sid>/bundle-20261018T001746Z/events.jsonl`, written by `lrh_state`
- the `transplant.json` `ts_first` field and its mtime
- `handoffs.jsonl` `phases`/`elapsed_s`. handoff-fire's T0 = row ts − `elapsed_s`, and `hf_phase` stamps integer
  seconds since T0 (`handoff-fire.sh:1026-1030`).
- the `locks/<sid>.{aborted,unconfirmed}-*` evidence-dir names, stamped by `date` in `lr-transplant.sh:453`

### 43e6eb4b (batch 000816Z): 1476.8 s

| segment | UTC | s | kitty calls inside | evidence |
|---|---|---|---|---|
| bundle, audit, salvage, context | 00:17:36.96 → 00:18:11 | 34.0 | none | bundle `assign` row; file mtimes 00:17:53–00:18:10 |
| precheck (`handoff-fire --probe-recycle-preconditions`) | 00:18:11 → 00:20:54 | 163 | P1–P5 (table 3a); **all answered** (`composer: empty`) | bundle `probed focus` |
| swap gate | → 00:20:55 | 1 | none | bundle `admitted gate` |
| `lr-transplant --phase admit` | 00:20:55 → 00:26:01 | 306 | none | `transplant.json` ts_first 00:21:13, mtime 00:26:01 |
| launcher mint, armed verdict, handoff-fire exec | → 00:26:06 | 5 | none | launcher mtime 00:26:02; `recycle-armed` 00:26:03; T0 = 00:30:54 − 288 |
| handoff-fire start-up and pre-gates | 00:26:06 → 00:30:50 | 284 | R1, R2; answered | `gates@284s` |
| **up-front kitty probe** | 00:30:50 → 00:30:53 | **3** | **R3: FAILED** | `kitty-probe@287s` |
| held row, owed-recycle row, exit 1 | → 00:30:54 | 1 | none | row ts, `elapsed_s` 288 |
| **post-hold stand-down** (`lr-handoff.sh:1960-2009`) | 00:30:54 → 00:41:43 | **649** | **none** | `locks/43e6eb4b…aborted-20261018T004143Z` |
| abort tail, `lrh_state HELD` | → 00:41:59 | 16 | none | bundle `HELD recycle` |
| NOTMOVED verdict, exit, worker `ev actuated` | → 00:42:13.79 | 14.8 | none | bundle `NOTMOVED`; events `actuated` |
| **total** | | **1476.8** | kitty-bearing segments ≤ 450 s; the failed call was 3 s | |

### 7b50757e (batch 000922Z): 1558.2 s

| segment | UTC | s | kitty calls inside | evidence |
|---|---|---|---|---|
| bundle | 00:17:36.90 → 00:18:11 | 34.1 | none | bundle `assign` |
| precheck | → 00:20:54 | 163 | P1–P5; answered | bundle `probed` |
| gate and admit | 00:20:54 → 00:25:25 | 271 | none | `transplant.json` ts_first 00:21:12, mtime 00:25:25 |
| launcher, armed verdict, exec | → 00:25:29 | 4 | none | T0 = 00:36:45 − 676 |
| pre-gates | → 00:27:28 | 119 | R1, R2; answered | `gates@119s` |
| up-front kitty probe | → 00:27:33 | 5 | R3: **passed** (connect + `kitty @ ls`) | `kitty-probe@124s` |
| self-id → intent row | → 00:33:37 | **364** | **none** (no kitty call between `:15435` and `:18481`) | `intent@488s` |
| pane→tty | → 00:33:54 | 17 | R4; answered | `tty@505s` |
| state, composer and focus gates, lock | → 00:35:46 | 112 | R5, R6; no hold | `detach@617s` |
| watcher fork → heartbeat record | → 00:36:36 | 50 | none | watcher `lstart` 00:35:55, `armed_at` 00:36:36 |
| **watcher pane proof** | → 00:36:45 | 9 | **R7: FAILED**, `it2 session list --json` rc=124 in 13 s (single attempt) | watcher log `/var/folders/…/handoff-recycle-47-1792283623-4hZ95E.log` |
| **post-hold stand-down** | → 00:43:21 | **396** | none | bundle `HELD recycle` |
| verdict, exit | → 00:43:35.09 | 14.1 | none | events `actuated` |
| **total** | | **1558.2** | | |

### Controls

- **The box, not kitty, sets the pace.** e739e5b5 (batch 002357Z) spent **1786 s** in its precheck (00:28:36 →
  00:58:22 **[m]**, bundle events). It refused at the limit gate (`handoff-fire.sh:12876-12952`), which runs before any
  kitty call, so that time contains zero kitty round-trips. The intent had expired 1106 s earlier, during the crawl.
- **Load at the time [m]** (`capacity-alarm.jsonl`, `load_1m`, ncpu 10):

  | UTC | 00:16:49 | 00:20:57 | 00:24:09 | 00:26:35 | 00:29:28 | 00:33:36 | 00:38:28 | 00:42:40 |
  |---|---|---|---|---|---|---|---|---|
  | load_1m | 286 | 285 | 319 | 340 | 326 | 332 | **396** | 314 |
  | per core | 28.6 | 28.5 | 31.9 | 34.0 | 32.6 | 33.2 | **39.6** | 31.4 |

- **The 649 s and 396 s stand-downs have no timestamp inside them.** Neither has a kitty call or a wait loop either
  (`lr-handoff.sh:1960-2009`, `lr-transplant.sh:721-769`). Two bounds are measured:
  - `lrh_held_reason` (`lr-handoff.sh:1297-1308`) returned `unreachable`. So it ran **before** 00:41:18 for pane 8, and
    before 00:40:53 for pane 47, the times of the subjects' own `recycle-held-busy` rows (§4).
  - The abort filed its evidence at 00:41:43.

  Where the ~10 minutes went is **not determined** from the logs.

---

## 3. The kitty remote-control call chain on the in-place path

Per-call bound = `timeout -k 3 S`, so S + 3 s worst case **[m]** in the code: `handoff-fire.sh:1135`, and
`lr-handoff.sh:143` for `lrh_kitty`. The watcher log confirms it: `rc=124 in 13s` for S = 10.
`HF_TIMEOUT_S=10` (`:1075`). Each kitty call reached the single socket `unix:/tmp/kitty-44163`. Exactly one
candidate exists: `ps` shows one kitty, pid 44163, and the `tried` set in `:2598-2600` removes the duplicate of
`$CC_TERM_KITTY_TO` against `kitty_sockets` **[m]**.

### 3a. Ordered chain

| # | file:line (caller → callee) | kitty call | per-call bound | retries / loop | worst-case s **[e]** (sum of bounds) |
|---|---|---|---|---|---|
| — | `lr-move-worker.sh:161` | none: reads `.kitty_listen_on` from the registry and passes `CC_TERM_KITTY_TO` (`:168`) | — | — | 0 |
| P1 | `lr-handoff.sh:1405` → `handoff-fire.sh:13007` `hf_remote_pane_term` → `:2606` `kitty_socket_answers` (`:1400`) | `kitty @ --to S ls` | 13 | if it does not answer: `kitty_socket_accepting` (6). If it answers: `:2610` `kt_window_field` (`:1561`) `kitty @ ls` (13), and on query failure `kitty_socket_accepting` (6). Re-asks only on accepting-but-silent: 3 attempts total (`:2645` `CC_REMOTE_PANE_TERM_TRIES`), with a 2 s sleep (`:2647`) | 3×32 + 2×2 = **100** |
| P2 | `:13022` `as_tty` → `:1870` `as_tty_classified` → `:1914` `_as_tty_query` → `kt_window_field` | `kitty @ ls` | 13 | 5 tries (`:1871` `HANDOFF_TTY_RETRIES`), 0.3 s sleep | 5×13 + 1.2 = **66.2** |
| P3 | `:13050` `kt_window_field … pid` | `kitty @ ls` | 13 | none | **13** |
| P4 | `:13078` `hf_focus_gate` → `lr-lib.sh:1376` → `handoff-fire.sh:3300` `hf_pane_focused` | `kitty @ ls` | 13 | (a focused pane adds composer reads) | **13** |
| P5 | `:13091` `composer_content` → `:4531/:4532`, long-read `:4620/:4621` | `it2 session read` → `bin/it2-kitty` `kitty @ get-text`. The inner bound of 15 s (`bin/it2-kitty:97`) is larger than the outer 10 s | 13 | up to 4 reads | **52** |
| — | `lr-handoff.sh:1864` `lrh_resolve_kitty_socket` | none: returns at `:189` because the worker already set `CC_TERM_KITTY_TO` | — | — | 0 |
| — | `lr-handoff.sh:1593` `lr-transplant --phase admit` | none | — | — | 0 |
| R1 | `lr-handoff.sh:1938` → `handoff-fire.sh:15338` `hf_remote_pane_term` | as P1 | 13 | as P1 | **100** |
| R2 | `:15372` `hf_remote_source_pin` → `:2691` `as_tty_classified` | as P2 | 13 | 5 tries | **66.2** |
| **R3** | `:15409` `hf_recycle_kitty_precheck` (`:1476`) → `:1484` `kitty_socket_accepting` (`:1435`; python3 `connect()` under `hf_bounded_s 3`, `CC_KITTY_CONNECT_TIMEOUT_S`) → if it accepted, `:1485` `kt ls` → `:1490` `hf_kitty_queue_depth` (`scripts/lib/kitty-queue.sh:36-41`, netstat under `_kq_to 3`) | connect + `kitty @ ls` + netstat | 6 / 13 / 6 | **none**: one shot by design (`:1457-1461`) | **25** (refused path 12). A non-zero rc → **HELD:unreachable** at `:15423-15429` |
| R4 | `recycle_fire` (`:19318` → `:18442`) → `:18524` `as_tty_classified` | `kitty @ ls` | 13 | 5 tries | **66.2** → HELD:unreachable at `:18528` |
| R5 | `:18612` `composer_content`, then `recycle_composer_gate` (`:18619-18631`) | `it2 session read` | 13 | polls for up to `CC_RECYCLE_DRAFT_WAIT` 180 s every 15 s | **≈232** (180 + one 52 s read set) → HELD:unreachable at `:5002/:5005` if unreadable |
| R6 | `:18878` `hf_focus_gate` | `kitty @ ls` | 13 | — | **13** |
| **R7** | `:18926` detach the watcher → `:18927` `await_armed` (25 ticks × 0.2 s) → `:18958` `await_pane_proof` (`:2012`, (10+3+5)×5 ticks × 0.2 s = 18 s) ← watcher `pane_proof` `:4027` | `it2 session list --json` (inner 15 s > outer 10 s) | 13 | **none** | **≈23** → HELD:unreachable at `:18963` |

### 3b. Worst-case arithmetic **[e]** (every call above runs to its bound)

- Precheck: 100 + 66.2 + 13 + 13 + 52 = **244 s**
- handoff-fire to the up-front probe: 100 + 66.2 + 25 = **191 s** → **435 s** of kitty time at most before the
  43e6eb4b hold
- On through the watcher's pane proof: + 66.2 + 232 + 13 + 23 ≈ **334 s** → **≈770 s** at most before the 7b50757e hold

### 3c. How 1476 s actually arises

The kitty chain's worst case (435 s) is less than a third of the measured 1476.8 s. And the calls in it did **not** run
to their bounds:
- P1–P5, R1 and R2 all answered.
- R3 failed in ≈3 s.

The 1476.8 s is the serial sum of slow non-kitty work at load 28–40 per core **[m]** (§2):

| segment | s |
|---|---|
| transplant admit | 306 |
| stand-down | 649 |
| handoff-fire start-up and pre-gates | 284, an upper bound on R1+R2 |
| precheck | 163, an upper bound on P1–P5 |
| bundle | 34 |
| other | ≈40 |

Non-kitty segments alone come to **1027 s, 70 %** **[m]**, by summing the §2 rows that hold no kitty call. The two
tick-counted waits stretched as well: `await_armed` is nominally 5 s and took 41–50 s for 7b50757e **[m]**, because each
`grep` + `/bin/sleep` fork slows down under load.

---

## 4. What emits `HELD:unreachable`, why kitty was called unreachable, and whether the session was left untouched

### 4a. The emission chain for 43e6eb4b

1. `handoff-fire.sh:15409` calls `hf_recycle_kitty_precheck`.
2. `:1484` `kitty_socket_accepting "unix:/tmp/kitty-44163"` returned non-zero, so `:1488` set the reason "the control
   socket … did not accept a connection".
3. `:1490` `q=$(hf_kitty_queue_depth)` → 0 → `:1495` "(0 queued)" → `return 1`.
4. `:15423-15429`, in order:
   - `emit_recycle_event recycle-held-unreachable` (row at 00:30:54 **[m]**)
   - `hf_recycle_owed_record` (`:2080`) writes `pane-close-queue/recycle-8.json`
   - prints "!! recycle HELD (kitty is not answering) … Nothing was typed and nothing was closed"
   - `exit 1`
5. `lr-handoff.sh:1939` sets `LRH_RCY_RC=1`. Then:
   - neither the no-shell check (`:1961`) nor the after-confirm forms (`:1975`) match
   - `:1986` `! lrh_source_retired` is true (no `.handed-off`)
   - `:1997` `lrh_held_reason` reads the newest `recycle-held-*` row for pane 8 since the fire → `unreachable`
   - `:2008` `lr-transplant --phase abort` → rc 0
   - `:2011` prints `verdict: HELD:unreachable`
   - `:2012` `lrh_state HELD`, `:2013` `lrh_verdict NOTMOVED`, `:2015` `exit 6`
6. `lr-move-worker.sh:173` writes `ev actuated "rc 6"`. `:174` uses `sed` to pull out `HELD:unreachable`. `:178` sets the
   W6 bound to 20 s for rc 6, and `:200` calls `finish NOTMOVED "HELD:unreachable — … (lr-handoff rc 6)"`.

For 7b50757e the first link is different. `:18958` `await_pane_proof` returned 3 because the watcher's single
`it2 session list --json` hit its bound (rc=124 in 13 s **[m]**, watcher log). That leads to the `:18963`
`recycle-held-unreachable` row, the `:18967` owed-recycle record, the `:18968` message and `:18974` `exit 1`. Steps 5
and 6 are the same.

### 4b. Why kitty was reported unreachable: the verdict was about a moment, not about the world

**[m]** Same socket, same kitty process: pid 44163, `kitty_lstart Thu Oct 15 05:01:28` in both prechecks, and still
the only kitty in `ps` now.

| UTC | observation | answered? | source |
|---|---|---|---|
| 00:18:37, 00:23:49 | pane-close-retry `kitty @ ls` (10 s bound) on `/tmp/kitty-44163` | yes; rows drained and no `kitty unresponsive` line after 10-17 21:01:52Z | `pane-close-retry.log` |
| 00:20:54 | both prechecks: P1–P5 including the composer read | yes | bundle events |
| 00:27:28–33 | 7b50757e up-front probe (connect + `kitty @ ls`) | **yes, ≤5 s** | `kitty-probe@124s` |
| **00:30:50–53** | **43e6eb4b up-front probe** | **no: "did not accept a connection (0 queued)"** | handoffs row |
| 00:31:41 | pane-close-retry: "recycle pane=8 terminal answers" | **yes, 48 s later** | `pane-close-retry.log` |
| 00:33:54 | 7b50757e `as_tty_classified` | yes | `tty@505s` |
| ≈00:36:32–45 | 7b50757e watcher `it2 session list --json` | no: rc=124 in 13 s | watcher log |
| 00:39:06 | pane-close-retry: "recycle pane=47 terminal answers" | yes | `pane-close-retry.log` |
| 00:40:15, 00:41:06 | the subjects' own recycles: probe in <1 s (`gates@17s kitty-probe@17s`, `gates@16s kitty-probe@16s`) | yes | handoffs rows |

The probe cannot say which of three causes produced its non-zero. This is the "two causes, one rc" trap one layer
further down:

- **`kitty_socket_accepting` (`:1435-1452`) folds every failure into rc 1.** That covers `ECONNREFUSED`, `ENOENT`, any
  other `OSError`, a `chdir` failure, and the probe process being killed by its own 3 s bound (rc 124/137). All of them
  print "did not accept a connection" (`:1488`).
  - The lesson's table reads a refusal as "a leftover socket, so retrying can only waste time".
  - On this box a **live** kitty refuses too. `docs/research/husk-panes-2026-09-30.md:88` measured "128 connections
    queued … 128 is the listen backlog, so further connects fail at once with `connection refused`". At `:29` it records
    recoverable stalls of 10–60 s, with accept bursts about 60 s apart.
- **"0 queued" is not evidence.** `hf_kitty_queue_depth` (`kitty-queue.sh:39-41`) runs netstat under a 3 s bound with
  `|| true`, and awk then prints `n + 0`. So a failed or timed-out netstat reads as 0.
- **The phase stamps cannot separate the cases.** The probe took 2–4 s **[e]**, from integer `hf_phase` stamps 284 → 287.
  That fits a 3 s connect bound firing followed by a quick netstat. It also fits a refusal at once followed by a ≈2–3 s
  netstat. The connect rc was not recorded.
- **Probe overhead now, for scale.** At load 13 per core, measured at 02:2xZ: `/usr/bin/python3 -c 'import os, socket, sys'` takes
  0.04 s (×3) and `netstat -anv -f unix` 0.01 s **[m]** (`/usr/bin/time -p`). At the incident's 33 per core neither was
  measured.

### 4c. Was the session left untouched?

**At the moment of the hold, yes.** R3 runs before self-id, the intent row, the tty, the composer, the confirm and the
watcher (`:15405-15430`), so nothing was typed and nothing was closed. The source was never retired
(`lr-handoff.sh:1986`). The abort withdrew the target copy, the tombstone and the lock (`lr-transplant.sh:721-769`).
While the admit-phase tombstone stood (00:21:13 → 00:41:43), prompts were still let through by
`hooks/handed-off-session-guard.sh:179`: `handed-off-guard.log` shows `allow-admit` at 00:31:34 and 00:40:25 **[m]**.

**Afterwards, no.** `hf_recycle_owed_record` (`:15425`, and `:18967` for 7b50757e) queued a "recycle owed" row even
though this was a **driver-form** recycle (`--source-pane`, run by the worker). `scripts/pane-close-retry.sh:249-263`
(`drain_recycle`) then used cc-notify to tell the **subject session** "RECYCLE RETRY: your --recycle of pane N … re-run
it as its own Bash call". That happened at 00:31:41 for pane 8 and 00:39:06 for pane 47 **[m]**. Both subjects complied
(`bash-commands.log` **[m]**):
- 7b50757e at 00:39:40
- 43e6eb4b at 00:40:37, and again at 00:41:45

Each of those recycles passed the kitty probe in under 1 s, **confirmed** the transplant (source retired to
`.handed-off`), held `recycle-held-busy` because the subject's own turn was in flight, and unconfirmed
(`locks/7b50757e…unconfirmed-20261018T004053Z`, `locks/43e6eb4b…unconfirmed-20261018T004117Z` **[m]**).
The move's own lr-handoff still held the admit and was still standing down at that point. Its abort filed
`aborted-20261018T004143Z`, an empty directory, 26 s after the subject's unconfirm.

So the subjects spent model turns, and their transcripts were retired and restored by a second actor. That race is
live: had `lrh_source_retired` (`lr-handoff.sh:1986`) run inside the confirm→unconfirm window, it would have reported
STRANDED (`:2020-2038`) over a live session.

---

## 5. Dead talk thread vs saturated box (from the lesson docs), and the cheap probe that separates them

| state | `connect(2)` | reply | queue (`netstat -anv -f unix`, rows on the path holding Recv-Q) | `KittyPeerMon` thread (`sample <pid> 1`) | recovers without a restart |
|---|---|---|---|---|---|
| leftover socket (kitty dead) | `ECONNREFUSED`/`ENOENT` | — | — | process absent | n/a |
| saturated / slow (`husk-panes-2026-09-30.md:29,94`) | accepts; refuses at once **only** while the backlog is over its limit | none within the client's window; bursts about 60 s apart | grows, then drains | **present** | **yes** (10–60 s stalls) |
| talk thread dead (`:88-92`) | accepts until 128 are queued, then refuses at once | never | **full (128)**, every row holding an unread request | **absent** | **no**: only a kitty restart helps |

- **The lesson was corrected the same day.** `docs/lessons/two-causes-one-rc-ask-a-lower-layer.md` (addendum,
  2026-10-17) first used kitty's own CPU (~0 % = dead, busy = saturated) and a raw connection held for 30 s as the
  discriminator. The CORRECTED block refutes this: the same pid 44163, idle and silent, recovered with no restart. So
  **idle CPU does not separate transient from dead**, and the stated rule is to treat accepting-but-silent as unknown and
  "retry on a schedule".
- **What the code actually treats as proof** (`scripts/lib/kitty-queue.sh:65-79` `kq_deaf`) is the conjunction of:
  - the accept queue at 128 or more
  - `sample` showing no `KittyPeerMon`, the thread that accepts remote-control peers

  A full queue alone is "slow, not deaf", and an unreadable sample is "not provably deaf".
- **Cheapest order** **[e]**, from the bounds already in the code:
  1. `connect()` (≤3 s). Before calling a refusal a leftover, check that the socket's owner is alive: the path names it
     (`/tmp/kitty-<pid>`; parsed already at `handoff-fire.sh:13042-13045`), so `kill -0 <pid>` plus `ps -o comm=` costs
     about 0 s. A live owner means a busy kitty refusing at once, which is retryable.
  2. netstat queue depth (≤3 s; 0.01 s measured now).
  3. `sample` for `KittyPeerMon` (≤15 s), only when the queue is at 128 or more.

---

## 6. Recommendation

### 6.1 A bounded retry with backoff for an unreachable socket

**Which call:** `hf_recycle_kitty_precheck`, at its call site `handoff-fire.sh:15409-15410` (or wrapped inside
`:1476-1496`).

- **Retry only states a retry can change:**
  - accepting-but-silent
  - connect "could not tell": the probe hit its own bound, rc 124/137
  - `ECONNREFUSED`/`ENOENT` while the socket's owner pid is alive and is kitty
- **Hold at once on:**
  - refused or `ENOENT` with a dead owner pid (the leftover case from the lesson)
  - rc 2 STUCK (`kq_deaf`: queue at 128 or more and no `KittyPeerMon`), which is the operator's restart
- **Bound:**
  - sleeps of 5, 10, 20 and 40 s (doubling), at most 5 attempts
  - stop once cumulative wall time passes `HF_KPROBE_BUDGET_S=120`
  - per attempt ≤6 + 13 + 6 = 25 s, so the hard worst case is ≈145 s **[e]**; a probe that passes costs 1–5 s
    **[m]** (`phases`, 9 runs)
- **Why 120 s** **[m]**:
  - the only refused-type hold on record cleared within 48 s (00:30:53 → 00:31:41)
  - husk-panes measured 10–60 s stalls with about 60 s between accept bursts, so 120 s covers two burst cycles
  - the ~10 h outage (`:1461`) stays a hold, because the bound caps it
- **Scope it to detached callers.** Add an env opt-in such as `HF_KPROBE_TRIES`, defaulting to 1 so today's single
  shot stays the default. That keeps the 120 s Bash-tool rule at `:1457-1461` for interactive callers. Set it in
  `lr-move-worker.sh:163-168`, next to `LR_INPLACE_AWAIT=0` (`:166`), which already declares that the caller is detached.
- **Expected effect on 43e6eb4b** **[e]**, replayed against the §4b timeline: an attempt at about +60 s (≈00:31:53)
  falls after the 00:31:41 answer, so the probe would most likely have passed. The recycle could still have held later,
  for example `HELD:load`, as the same pane did at 02:05.
- **Apply the same to R7**, the watcher pane proof (`:4027`, awaited at `:2012-2023`). It is one
  `it2 session list --json` under an outer 10 s bound, around an inner kitty bound of 15 s (`bin/it2-kitty:97`). That is
  the same inner-larger-than-outer inversion already fixed for split (`HF_SPLIT_TIMEOUT_S`, `:1098`) and send
  (`HF_SEND_TIMEOUT_S`, `:1105`). Give it a derived bound
  (inner + slack) and 2 attempts inside a correspondingly larger `HANDOFF_PANE_PROOF_TICKS`. This listing is what held
  7b50757e.

### 6.2 Fail fast instead of a 25-minute stand-down

1. **Ask reachability before anything moves.** In `--probe-recycle-preconditions`, right after `hf_remote_pane_term`
   resolves the terminal (`handoff-fire.sh:13020`, which also exports `CC_TERM=kitty`), call the same probe with its
   retry. On failure, call `prp_verdict "HELD:unreachable" 3`, or `HELD:wedged` for rc 2.
   - `lr-handoff.sh:1414-1418` already turns that into "PRECHECK HELD … NOTHING has been transplanted" with rc 6, so
     there is no admit, no tombstone, no abort and no owed row.
   - A kitty that is deaf at the start then costs ≈34 s + ≤145 s **[e]**, instead of ≈800 s of admit and pre-gates plus
     ≈650 s of stand-down **[m]**.
   - One detector, reused (the rule recorded in the `kitty-queue.sh` header). The alternative site is
     `lr-move-worker.sh:156-160`, between the abort check and `ev actuate`, reading the socket the way `:161` does.
2. **Make the stand-down attributable, then fast.** Add `lrh_state` stamps:
   - at `lr-handoff.sh:1940` (handoff-fire returned, with its rc)
   - before `:1997`
   - around `:2008`

   The 649 s and 396 s gaps are unexplained today.
3. **Make the probe's verdict three-state and honest:**
   - `kitty_socket_accepting` (`:1435-1452`): distinct exit codes for accepted, refused, `ENOENT`, other and bound fired.
   - `hf_kitty_queue_depth` (`kitty-queue.sh:39-41`): print `?` rather than `0` when netstat failed.
   - Put the raw connect rc and ms, the `ls` rc and the queue reading into the `recycle-held-unreachable` detail
     (`:15424`), so the next incident can be attributed.
4. **Do not nudge the subject about a driver's recycle.** When `RCY_REMOTE=1` and a record id is set
   (`LR_RECORD_ID`/`HF_RECYCLE_ATTEMPT`, so the placer owns the retry), skip `hf_recycle_owed_record` at `:15425`,
   `:18529` and `:18967`. Alternatively, write `driver=remote` into the row and have `drain_recycle`
   (`pane-close-retry.sh:249-263`) skip it. This removes the confirm/unconfirm race shown in §4c.
