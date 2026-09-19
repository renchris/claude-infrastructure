# U14 — latency floor of the in-place limit-recovery chain

Measured 2026-09-19 on the live box, read-only. Repo root `R=/Users/chrisren/Development/claude-infrastructure`.
Every timing below is a `time` of the real command, printed verbatim in § A.

---

## 0. HEADLINE

**The census is 99.8% of the identification cost and it is pure fork overhead.**
`lr-fleet.sh --locate` = **40.3 / 64.5 / 86.1 s** (three runs today, cold→warm).
A single-pass Python doing *strictly more* work over the same 2,158 files = **0.148 s**.
That is a **272×–582× gap**, and `--one SID` pays it too (`lr-fleet.sh:426`) even when the caller
already handed it `--source-pane` — the 0.039 s cheap path exists 2 lines below at `:428-433`
and is reached only when the 64 s census *misses*.

Second finding: **no field the statusline renders is a unique key.** `statusline.sh:284-306`
emits `DIR (COMMIT) BRANCH · EFFORT` + an account glyph and **no sid, no pane id**. In the live
registry `account + cwd-basename` collides **5 ways, up to 4-deep** (`claude-tertiary` +
`claude-infrastructure` = 4 rows). A registry index cannot fix a screenshot that carries no key.

---

## 1. TABLE OF CONSTANTS — every sleep/timeout/poll/retry on the chain

### 1.1 `scripts/limit-recover/lr-fleet.sh`

| file:line | constant | default | what it bounds | on the critical path? |
|---|---|---|---|---|
| `lr-fleet.sh:283` | `LR_FLEET_CAP_WAIT_S` | **600** | total capacity park before `PARKED` | YES — cost the 12:01 fire 600 s + census = **658 s wall** (run `one-20260919T170450Z`, dir ts 17:04:50 → results.tsv 17:15:48) |
| `lr-fleet.sh:283` | `LR_FLEET_CAP_IVL_S` | **20** | re-probe interval inside that park | YES — 30 probes max |
| `lr-fleet.sh:289` | `sleep "$ivl"` | 20 | the park's sleep | YES |
| `lr-fleet.sh:426` | *(no constant — structural)* | — | `--one` runs the FULL `lf_locate` census to find one already-named sid | **YES — 40–86 s, unconditionally** |
| `lr-fleet.sh:187-196` | *(no constant — structural)* | — | per-file `tail -c 20000` + 2 `grep` forks × 2,579 files | **YES — measured 61.1 s for the loop alone** |
| `lr-lib.sh:23` | *(no constant — structural)* | — | lists BOTH `~/.claude` and `~/.claude-next`, whose `projects/` is a symlink to the same dir → **421 of 2,579 files (16.3%) scanned twice**, deduped afterwards at `lr-fleet.sh:257-262` | YES |

### 1.2 `scripts/limit-recover/lr-handoff.sh`

| file:line | constant | default | bounds |
|---|---|---|---|
| `lr-handoff.sh:83` | `LRH_OSA_TIMEOUT_S` | **15** | every osascript/it2 call (`-k 3`, `:96`) |
| `lr-handoff.sh:150` | `LRH_KITTY_SETTLE_S` | **4** | fixed settle after a kitty spawn |
| `lr-handoff.sh:174` | loop cap `n -lt 16` | 16 | pane-ancestry walk (no sleep) |
| `lr-handoff.sh:526` | — | — | `lr-preseed-env.sh` call — measured **0.057 s** to parse the 228 KB target `.claude.json` |
| `lr-handoff.sh:469` | — | — | sha verify is delegated to `lr-transplant.sh` (below) |

### 1.3 `scripts/limit-recover/lr-transplant.sh` — **zero sleeps, zero timeouts**

| file:line | cost |
|---|---|
| `:32-33` | 2× `python3 -c realpath` ≈ **0.09 s** (two interpreter starts; `readlink -f`/`cd&&pwd` would be ~0) |
| `:74` | `cp -p` |
| `:86-87` | **2× `shasum -a 256`** over the transcript. Measured 0.058 s on the 2.6 MB `cb227486` transcript. Tail risk: the largest transcript in the fleet is **241 MB** (`~/.claude-quaternary/.../4101dbdf….jsonl`) → cp + 2 shas ≈ **5 s** |
| `:99` | `mv` source → `.handed-off` |

### 1.4 `scripts/limit-recover/lr-fire-resume.sh` (the relaunch the pane actually execs)

| file:line | constant | value | bounds |
|---|---|---|---|
| `:322` | `cc_capacity_admit lr-fire-resume` | — | **THE 2026-09-19 PARTIAL ROOT CAUSE.** Exit 9 before `exec expect`. Load term is ON here; `CC_ADMIT_LOAD_TERM=off` set in the *invoking* session never reaches this process |
| `:433` | `set timeout` | **300** | global expect timeout |
| `:474` | `sleep 1` per arrow | 1 s × steps | menu navigation, 1 s per `\033[B` |
| `:485` | `set timeout` | **10** | menu-label readback |
| `:495` | `set timeout` | 300 | restore |
| `:522` | `sleep 1` | 1 | resume-menu settle |
| `:532` | `sleep 1` | 1 | trust-dialog settle |
| `:545` | `sleep 1` | 1 | folder-select settle |
| `:552` | `sleep 2` | **2** | READY → pre-prompt settle |
| `:554` | `sleep 1` | **1** | after `\025` (^U clear) |
| `:556` | `sleep 1` | **1** | after prompt text, before CR |
| `:570` | `set timeout` | **6** | submit-confirm window; re-sends CR on timeout (`:575`) |
| `:582` | `set timeout` | 300 | restore before `interact` |

**Fixed, unconditional dead time on the happy READY path: 2+1+1 = 4 s** (`:552,554,556`), plus up
to 6 s per un-confirmed submit.

### 1.5 `scripts/handoff-fire.sh` recycle region

| file:line | constant | default | bounds |
|---|---|---|---|
| `:894` | `HANDOFF_IT2_TIMEOUT_S` | **10** | every it2/kitty RPC |
| `:917` | `HANDOFF_SPLIT_TIMEOUT_S` | `IT2_KITTY_TIMEOUT_S(15)+30` = **45** | pane split |
| `:1521` | `HANDOFF_TTY_RETRY_SLEEP_S` | **0.3** | tty-resolve retry |
| `:1654` | `HANDOFF_PANE_PROOF_TICKS` | `(10+3+5)*5` = **90 ticks × 0.2 s = 18 s** | pane-proof poll |
| `:2284` | `FIRE_TYPE_ATTEMPTS` / `FIRE_TYPE_SETTLE` | **4 / 0.5** | verified type retry |
| `:2285` | `FIRE_TYPE_PRESETTLE` | 0.12 | pre-send settle |
| `:2716` | `FIRE_PASTE_READBACK_TRIES` | 8 | paste read-back |
| `:6445` | `HF_SELFCLOSE_GRACE_S` / `_STEP_S` | **180 / 5** | self-close grace (not on recycle path) |
| `:6509` | `sleep 2` × 4 tries | 8 s | pane-close retry |
| **`:6605`** | **`HF_RECYCLE_SHELL_WAIT_S`** | **600** | watcher waits for the pane to reach a shell after `/exit` |
| `:6615` | `CC_RECYCLE_BGWORK_EVERY_S` | 15 (floor 3) | bgwork-dialog probe cadence |
| `:6613` | `CC_RECYCLE_BGWORK_MAX` | 2 | max stray keystrokes |
| **`:6619`** | **`sleep 3`** | **3** | **the shell-wait poll quantum — hard-coded, not a seam** |
| `:6628` | `waited % 15` | 15 | pane-vanish probe (`session list` ≈ 36 ms) |
| `:6682-6689` | nudge checkpoints | **60 / 150 / 300 s** | gated CR / one retype of `/exit` |
| **`:6786`** | **`sleep 2`** | **2** | fixed shell-prompt settle after claude exits — hard-coded |
| `:6788-6791` | 2 attempts × `sleep 3` | 6 | relaunch type retry |
| **`:6811`** | **`for _ in $(seq 1 15); do sleep 3; …`** | **45 s** | wait for `cc_alive`. **Sleeps BEFORE the first check** → minimum detection latency is 3 s even if CC is up in 0.4 s |
| **`:6815`** | same loop again after one retype | **+45 s** | → the verbatim `"no claude process appeared within 90s"` at `:6879` |
| **`:6782`** | `RCY_ENGAGE_TIMEOUT` | **180** | engagement window |
| **`:6783`** | `RCY_ENGAGE_INTERVAL` | **5** | engagement poll quantum |
| `:6859` | `sleep "$RCY_ENGAGE_INTERVAL"` | 5 | " |
| `:9222` | `FIRE_ENGAGE_TIMEOUT_BASE/MAX` | 90 / 360 | fire-path alarm window |
| `:11634` | `CC_RECYCLE_DRAFT_WAIT` / `_IVL` | **180 / 15** | composer gate — defers `/exit` over a held draft |
| `:11788` | `max = 600 + 180 + 120` | **900** | `recycle_await_verdict` ceiling |
| `:11801` | `HF_RECYCLE_AWAIT_IVL` | **5** | verdict-log poll quantum (adds ≤5 s to every reported verdict) |
| `:441/443` | `ACCOUNT_SWEEP_THROTTLE_S` / `RELOGIN_TIMEOUT_S` | 60 / 90 | pre-fire account sweep |
| `:8605` | `CC_FIRE_INFLIGHT_MAX_S` | 1800 | in-flight fire staleness |

### 1.6 `scripts/lib/capacity-admit.sh`

| file:line | constant | default |
|---|---|---|
| `:161` | `CC_HW_DEFAULT_MAX_LOAD_PER_CORE` | **2.0** |
| `:555,601,636,889` | `CC_ADMIT_LOAD_TERM` | **on** (comment at `:153` says it is a wrong input and "has been off on the Agent-tool path since Wave D" — but it is still ON for `lr-fire-resume`) |
| `:92` | `CC_ADMIT_MIN_HEADROOM_GB` | 4 |

---

## 2. THE THEORETICAL MINIMUM for ONE in-place recovery, idle box

### 2.1 What it costs TODAY (measured, `~/.reso/limit-recover/fleet/`)

| run dir | wall (dir ts → results.tsv mtime) | verdict |
|---|---|---|
| `one-20260919T170450Z` | 17:04:50 → 17:15:48 = **658 s** | parked/capacity |
| `one-20260919T171910Z` | 17:19:10 → 17:21:05 = **115 s** | **RECOVERED** |
| `one-20260919T172126Z` | 17:21:26 → 17:23:54 = **148 s** | PARTIAL |
| `one-20260919T174403Z` | 17:44:03 → 17:46:35 = **152 s** | PARTIAL |
| `one-20260919T174851Z` | 17:48:51 → 17:51:26 = **155 s** | PARTIAL |
| `one-20260919T175207Z` | 17:52:07 → 17:54:45 = **158 s** | PARTIAL |

The 4 PARTIALs are 148–158 s each and **every one of them is `census(40–86 s) + 90 s dead-wait**
(`:6811`+`:6815`) for a `claude` that `lr-fire-resume.sh:322` had already refused with exit 9.
The 90 s bought *detection*, not recovery; the verbatim line is
`!! relaunch typed but no claude process appeared within 90s — fallback comment typed into pane`
(`handoff-fire.sh:6879`, reproduced in all four `.stderr` files).

### 2.2 Step budget — today vs achievable vs irreducible

| # | step | today | achievable | irreducible | source |
|---|---|---|---|---|---|
| 1 | census / identify | **40–86 s** | **0.15 s** | ~0.05 s | `lr-fleet.sh:426`; § A3/A4 |
| 2 | rank target account | 0.47–1.09 s | **0 s** (run ∥ with 1) | 0 | § A5 |
| 3 | capacity gate | 0 or **600 s** | 0 | 0 | `lr-fleet.sh:283` |
| 4 | transplant (cp + 2 sha + tombstone) | 0.06 s (2.6 MB) | 0.03 s (1 sha) | 0.03 s | `lr-transplant.sh:86-87`; § A6 |
| 5 | preseed | 0.06 s | 0 (∥ with 6) | 0 | § A7 |
| 6 | arm watcher + compose relaunch | ~1.5 s | 1.0 s | 1.0 s | `handoff-fire.sh:894` |
| 7 | `/exit` → shell detected | real exit ~3 s + **3 s poll quantum** + **2 s fixed** = **~8 s** | 3.5 s | **~3 s** (CC teardown) | `:6619`, `:6786` |
| 8 | type relaunch into shell | ~1 s | 1 s | 1 s | `:2284` |
| 9 | TUI boot → `cc_alive` | real ~4 s, **detected at a 3 s quantum, min 3 s, cap 45 s** | 4.2 s | **~4 s** (node+TUI start) | `:6811` |
| 10 | `lr-fire-resume` fixed expect sleeps | **4 s** | 0.6 s | ~0.3 s | `:552,554,556` |
| 11 | submit-confirm | ≤6 s | 0.5 s | 0.2 s | `:570` |
| 12 | first real assistant turn (= "engaged") | 15–60 s | 15 s | **~12–15 s** (one model round-trip on the ingest brief) | `recycle_engaged`, `:6851` |
| 13 | verdict surfaced to the caller | **+0–5 s** poll | +0.5 s | 0 (event, not poll) | `:11801` |
| | **TOTAL** | **115–158 s** (658 s if parked) | **≈26 s** | **≈21 s** | |

**The irreducible floor is ~21 s** and it is three physical events: CC teardown (~3 s), CC boot
(~4 s), one model round-trip to produce the assistant turn that *is* the definition of engaged
(~14 s). Everything else — 94–137 s of today's wall — is census, poll quantization, and fixed sleeps.

### 2.3 What can run in parallel or be skipped

**Skip outright**
- `lf_locate` when `--one SID` is given (`lr-fleet.sh:426`). The cheap resolver at `:428-433`
  already does the job in **0.039 s** and is only reached on a census *miss*. Invert the order.
- The duplicate config dir. `lr-lib.sh:23` enumerates `~/.claude` **and** `~/.claude-next`, whose
  `projects/` is one symlink (`readlink ~/.claude-next/projects` → `/Users/chrisren/.claude/projects`).
  Dedupe by `realpath` **before** the scan, not by `lf_dedup_mirror` after it: −16.3% of files.
- One of the two `shasum` calls in `lr-transplant.sh:86-87` — hash the source once, hash the
  destination once is the point, but `cp` + `cmp -s` is equivalent and single-pass.
- The two `python3 -c realpath` starts at `lr-transplant.sh:32-33` (≈0.09 s of pure interpreter start).

**Parallelize**
- (1) census ∥ (2) `claude-accounts --rank` ∥ `kitty @ ls` — three independent reads, currently serial.
- (5) preseed ∥ (6) watcher arm — preseed writes the *target* config, the watcher touches the *pane*.
- **Fleet-wide, the big one:** N sessions are fully serialized today (each `lr-fleet --one` re-runs
  its own census *and* its own `lf_capacity_wait`). N recoveries share no resource except the
  per-sid lock dir (`lr-transplant.sh:60`) and the account store. One census + N concurrent
  transplants/recycles turns 5×150 s = 750 s into ~1×0.2 s + max(150 s) ≈ 150 s.

---

## 3. SCREENSHOT → IDENTIFIED, with a registry index

### 3.1 The index already exists and is fast

`~/.claude/cc-registry/<paneUUID>.json` — 31 files, 26 parseable, one row per pane:

```json
{"paneUUID":"140","name":"wt-pool-2-140","cwd":"/Users/chrisren/Development/.worktrees/wt-pool-2",
 "account":"claude-tertiary","pid":62675,"startedAt":1789843173000,
 "session_id":"98f02458-7842-4bc9-9040-f18846fa1f18","surface":"pane","lstart":"Sat Sep 19 18:39:32 2026"}
```

- full index parse, all rows: **0.242 s** (≈0.09 s of that is `python3` startup; a prebuilt
  single-file index read by `jq` or plain shell is **<50 ms**)
- `kitty @ --to unix:/tmp/kitty-73832 ls`: **0.177 s** → 16 live panes
- **pane id → sid is O(1):** `cat ~/.claude/cc-registry/117.json`, ~2 ms.

So **if the screenshot yields a pane id, identification is ~5 ms and the <2 s target is met 400× over.**

### 3.2 …but today's screenshot yields no key, and this is the blocker

`statusline.sh:284-306` composes `OUTPUT` as:

```
:284/286  OUTPUT="${DIR}${DIRTY}"        # basename of cwd
:290      OUTPUT="${OUTPUT} (${COMMIT})" # short git sha
:294      OUTPUT="${OUTPUT}  ${BRANCH}${DIRTY}"
:306      OUTPUT="${OUTPUT} · ${EFFORT}"
:486      echo -e "${GLYPH_PREFIX}${PCT_SEG}${OUTPUT}${RESET}"   # glyph = account number, PCT = context %
```

**No session id. No pane id.** The join key a screenshot offers is `account + cwd-basename`
(+ a git sha that is identical across every session in one worktree, + effort).

Collision census over the live registry (§ A8):

```
acct+cwdbase collisions: ('claude-quaternary','wt-cc-095358-75429')=2
                         ('claude-quaternary','claude-infrastructure')=2
                         ('claude-next','wt-pool-2')=2
                         ('claude-tertiary','claude-infrastructure')=4
                         ('claude-next','claude-infrastructure')=3
cwdbase-only collisions: 'claude-infrastructure'=10, 'wt-cc-095358-75429'=3, 'wt-pool-2'=3
```

**The best available key is 4-way ambiguous today.** That matches the lead's observation that three
sessions shared `claude-infrastructure`; the registry says it is now ten.

Second defect: the registry holds **26 rows against 16 live kitty panes** — 10 stale rows. Any
lookup must intersect with `kitty @ ls` (0.177 s) or it will return a dead pane.

### 3.3 The minimum, by what the screenshot carries

| screenshot carries | lookup | time |
|---|---|---|
| pane id (`#117`) | `cat ~/.claude/cc-registry/117.json` | **~2 ms** |
| sid8 (`cb227486`) | prefix-scan 26 registry rows | **~50 ms** (shell) / 0.24 s (python) |
| **today: acct + cwd-basename** | scan + intersect with `kitty @ ls` | 0.2 s **but returns 1–4 candidates — not an identification** |
| keyword from the pane body | `kitty @ get-text --match id:N` × 16 live panes | ~16 × 40 ms ≈ **0.7 s**, unique |

**Verdict: <2 s is trivially reachable on time and is blocked purely on the KEY.** The one-line
fix is in `statusline.sh` — `.session_id` is already parsed into the payload at `:79` and
`$KITTY_WINDOW_ID` is already referenced at `:415-416`, so appending `· 117/cb227486` costs one
`printf` and zero new reads.

---

## 4. THE 100TH-PERCENTILE TARGET, and the constants that must change

### 4.1 Targets

| stage | target | basis |
|---|---|---|
| screenshot/keyword → **identified** (sid, pane, cfg, tier, account) | **< 300 ms** (<2 s is 6× slack) | registry read 2–50 ms + `kitty @ ls` 177 ms, both measured |
| identified → **transplanted** (target chosen, transcript moved, sha-verified, tombstoned) | **< 2 s** | rank 0.5 s ∥ transplant 0.06 s ∥ preseed 0.06 s |
| transplanted → **engaged** (a real assistant turn), idle box | **< 30 s** | § 2.2: 21 s irreducible + ~5 s of tightened quanta |
| the operator's shell is **unblocked** | **< 1 s** (fire-and-watch, not fire-and-wait) | verdict must be an event, not a 5 s poll |
| engaged, **box under load** | **< 5 min** | `LR_FLEET_CAP_WAIT_S` 600 s is the only thing that can exceed this |
| **N sessions** recovered | **≈ max(single), not N × single** | no shared resource but the per-sid lock |
| any failure | **named within 10 s of the deciding event**, never after a 90 s dead-wait | § 4.2 item 6 |

### 4.2 The constants and lines that must change, ranked by seconds recovered

| # | change | file:line | saves |
|---|---|---|---|
| 1 | **Replace the per-file `tail`+2×`grep` loop with one Python/`awk` pass.** Benchmark: 2,158 files, tail 20 KB, regex + last-assistant classification = **0.148 s** vs the shipped loop's 61.1 s | `lr-fleet.sh:187-196` (+ `lf_kinds_of:145`, `lf_err_age_s:167`, and the inline python at `:203-214` — three interpreter starts *per matching file*) | **40–86 s → 0.15 s** |
| 2 | **`--one SID` must not run the census.** Try the 0.039 s resolver first; run `lf_locate` only if it misses | `lr-fleet.sh:426` vs `:428-433` | **40–86 s per unit** |
| 3 | **`LR_FLEET_CAP_WAIT_S` 600 → ~60**, and drop the load term for this caller (the comment at `capacity-admit.sh:153` already calls it a wrong input and it is already off on the Agent-tool path) | `lr-fleet.sh:283`; `capacity-admit.sh:555/601/636` | up to **600 s** |
| 4 | **`lr-fire-resume` must inherit the caller's admission decision.** Today `lr-fleet` waits out its *own* gate, then the relaunch is refused by a *second*, differently-configured gate inside the pane (exit 9) — the 4 PARTIALs | `lr-fire-resume.sh:322`; pass `CC_ADMIT_*` through the launch script `lr-handoff.sh` writes | **4 of 5 failures today** |
| 5 | **Poll quanta 3 s → 0.3 s, and check BEFORE sleeping.** `:6811`/`:6815` sleep first, so a CC that is up in 400 ms is detected at 3 s | `handoff-fire.sh:6619, 6788-6791, 6811, 6815` | ~5 s + removes a 3 s floor |
| 6 | **Shrink the dead-wait and make it say WHY.** 45+45 s at `:6811/:6815` is a fixed cost on every failure. `lr-fire-resume` exits **9** — capture that rc and report `capacity-refused` in 2 s instead of `no claude process appeared within 90s` in 90 s | `handoff-fire.sh:6811-6815, 6879` | **88 s per failure**, and converts an unattributed husk into a named cause |
| 7 | **Delete the 3 fixed expect sleeps on the happy path**; they are unconditional | `lr-fire-resume.sh:552 (2 s), :554 (1 s), :556 (1 s)` | **4 s** |
| 8 | **`sleep 2` fixed shell settle → poll** | `handoff-fire.sh:6786` | 2 s |
| 9 | **`RCY_ENGAGE_INTERVAL` 5 → 1** (the check is a cheap transcript grep) | `handoff-fire.sh:6783, 6859` | ≤4 s |
| 10 | **`HF_RECYCLE_AWAIT_IVL` 5 → 0.5, or make the watcher write a fifo/`kill -USR1`** so the verdict is an event | `handoff-fire.sh:11801` | ≤5 s, and unblocks the caller |
| 11 | **`realpath`-dedupe config dirs before the scan** (`~/.claude-next/projects` is a symlink to `~/.claude/projects`) | `lr-lib.sh:23` | 16.3% of the scan |
| 12 | **Emit `sid8` and/or the pane id in the statusline** — `.session_id` is already in the payload at `:79`, `$KITTY_WINDOW_ID` already referenced at `:415-416` | `statusline.sh:284-306` | turns a 4-way-ambiguous screenshot into an O(1) key |
| 13 | **Liveness-intersect the registry** (26 rows vs 16 live panes) before answering a lookup | new, on top of `~/.claude/cc-registry` + `kitty @ ls` (0.177 s) | prevents recovering a dead pane |
| 14 | **Fan the fleet out.** One census, N concurrent `lf_one` | `lr-fleet.sh:364-400` | N×150 s → ~150 s |
| 15 | Drop one `shasum` (use `cmp -s`) and the 2 `python3 -c realpath` starts | `lr-transplant.sh:32-33, 86-87` | ~0.12 s (≈2.5 s on the 241 MB tail case) |

### 4.3 Resulting budget

```
identify            0.15 s   (1,2,11)   was 40–86 s
rank ∥ transplant   0.5  s   (14)       was  0.6 s serial
preseed ∥ arm       1.0  s   (5)        was  1.6 s
/exit → shell       3.5  s   (5,8)      was ~8 s
type + boot         5.2  s   (5)        was ~7 s + 3 s floor
submit              1.1  s   (7)        was ~5 s
first assistant     14   s   —          irreducible
verdict             0.5  s   (10)       was ≤5 s
────────────────────────────────────────────────────
TOTAL              ≈26 s     vs 115–158 s measured today, 658 s when parked
```

**Engaged in <30 s on an idle box; <5 min under load is bounded by item 3 alone.**

### 4.4 Fault visibility — what makes it non-fire-and-forget

Today the four failure modes are legible only by reading a `.stderr` under
`~/.reso/limit-recover/fleet/<run>/`. The chain already emits `emit_recycle_event`
(`handoff-fire.sh:6795, 6843, 6866, 6874`) and `hf_alarm` — the gap is that **`lr-fleet` reports
`PARTIAL` with no cause**. `lf_one` maps only rc 4 → PARTIAL (`lr-fleet.sh:335-338`); it should
carry the watcher's own verdict token (`capacity-refused` / `vanished` / `never-engaged` /
`relaunch-write-failed`) into `results.tsv`, since `recycle_await_verdict:11794` already greps
exactly those five strings out of the log.

---

## A. RAW MEASUREMENTS (verbatim)

**A1** `time bash $R/scripts/limit-recover/lr-fleet.sh --locate` (cold, 1st):
`18.13s user 23.19s system 47% cpu 1:26.11 total` → 9 rows

**A2** same, 2nd run: `18.67s user 24.29s system 66% cpu 1:04.46 total`
same, 3rd run: `16.39s user 18.89s system 87% cpu 40.327 total`

**A3** the raw scan mechanism in isolation — `tail -c 20000` + 2 `grep` per file over the 5 dirs
(2,579 paths): `23.20s user 20.04s system 70% cpu 1:01.09 total`, matched=7

**A4** single-pass Python, same 2,158 unique files, tail 20 KB + regex + last-assistant classify:
`blocked=23 scanned=2158` / `0.06s user 0.07s system 87% cpu 0.148 total`

**A5** `time claude-accounts --json >/dev/null` → `0.38s user 0.05s system 58% cpu 0.729 total`
`time claude-accounts --rank general` → `0.47s user 0.45s system 84% cpu 1.092 total` → `next2`
`time claude-accounts --rank fable` → `0.36s user 0.05s system 87% cpu 0.467 total` → `next2`
(both now exclude `next=weekly/fable-exhausted`, `next4=5h-cutoff`, `next3=kmax-concurrency`)

**A6** `time bash $R/scripts/wrap-ledger.sh --machine >/dev/null` →
`6.73s user 1.14s system 86% cpu 9.137 total` — **9.1 s; it is not on the recovery path and must
never be put on it.**

**A7** transplant legs: 2× `shasum -a 256` on a 2.6 MB transcript = `0.058 s`; preseed's parse of
the 228 KB `~/.claude-secondary/.claude.json` = `0.057 s`; cheap sid→cfg resolver (the
`lr-fleet.sh:428-433` fallback) = `0.039 s`.

**A8** registry: 26 parseable rows / 31 files, full parse `0.242 s`;
`kitty @ --to unix:/tmp/kitty-73832 ls` = `0.177 s`, 16 live panes.
Collisions as printed in § 3.2.

**A9** corpus: 2,579 enumerated paths across 5 config dirs, 2,158 unique
(`readlink ~/.claude-next/projects` → `/Users/chrisren/.claude/projects`), **3.0 GB** total;
largest single transcript 241,368,760 B.

**A10** verbatim failure line, all four PARTIAL runs
(`~/.reso/limit-recover/fleet/one-2026091917{2126,4403,4851,5207}Z/*.stderr`):
```
!! recycle did NOT verify — watcher verdict:
!! relaunch typed but no claude process appeared within 90s — fallback comment typed into pane
```
and the successful one (`one-20260919T171910Z`):
```
→ recycle VERIFIED: → relaunched + ENGAGEMENT CONFIRMED in 112 (a real assistant turn, not just a process)
```

## B. LABELLED GUESSES (not measured — no write/fire permitted in this unit)

- CC teardown on `/exit` ≈ 3 s and CC TUI boot ≈ 4 s. Inferred from the 3 s poll quantum at
  `:6619`/`:6811` resolving within 1–2 ticks in the RECOVERED run; **not directly timed.**
- First-assistant-turn latency 12–15 s for the ingest brief. Inferred from the RECOVERED run's
  115 s wall minus the measured census and the known fixed sleeps; **not directly timed.**
- Item 5's "3 s → 0.3 s" assumes `pane_cc_state` is cheap enough to poll at 3 Hz. `pane_enumerated`
  is documented at ~36 ms (`handoff-fire.sh:6626`); `pane_cc_state` reads the tty's process list
  and is presumably comparable, **but I did not time it.**
