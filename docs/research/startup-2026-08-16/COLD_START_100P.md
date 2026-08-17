# Cold start, 100th percentile — the architecture

**A `claude` launch costs 1.75 s to a typable box and 5.72 s to a box that can actually start a
turn, and 69% of that is ONE hook that is killed by its own timeout and throws its work away.**
The other three components are the zsh entrypoint (237 ms, ~60% recoverable), the binary's own boot
(632 ms, upstream-owned and near-irreducible), and the config directory (722 ms, of which 600 ms is
an unexplained stall inside `showSetupScreens()` that nobody on either side has diagnosed). Fixing
the hook and trimming the shell gets a uniform **~1.61 s to a usable turn** — the same number on
every pane, with an 11–30 s silent tail removed. Everything below 1.6 s requires an upstream change,
and this document says so rather than promising it.

- **Evidence base:** 8 measurement axes + an adversarial verification pass, 2026-08-16, this box.
  Per-axis detail: `measure-{shell-fn,launcher-wrapper,sessionstart-hooks,mcp-servers,
  config-discovery,statusline-tui,regression-archaeology,upstream-knobs}.md` in this directory.
- **Every figure here is median-of-n≥3** on a box at load 14–24 with ~24–28 live sessions, which is
  the operator's real working condition. Where a figure is COMPOSED from two separately-measured
  spans rather than measured end-to-end, it is labelled COMPOSED and the residual is stated.

---

## 0. Three corrections that must land before anything is scheduled

**C1 — The brief's launch chain is wrong, and it is the single most expensive wrong belief here.**
`_claude_pinned` **does not exist** in `~/.zshrc` (`grep -n '_claude_pinned' ~/.zshrc` → no hits).
`claude()` at `~/.zshrc:451` sets `_bin="$HOME/.claude-220/node_modules/.bin/claude"` (`:496`) and
execs it through `$HOME/.claude/bin/cc-close-attrib` (`:502`, `:505`). `~/bin/claude-latest` appears
in the rc only at `:173`/`:175`, inside `claude-prev()` — the legacy stable-2.1.114 track.
Confirmed live: `ps -eo command= | grep -o '/Users/chrisren/\.claude[^/ ]*/node_modules/\.bin/claude' | sort | uniq -c`
→ **28 processes, all `.claude-220`, zero under `.claude-versions`**.
Consequence: the "~1.3 s spent before any session begins" in the brief is **0 ms of the operator's
cold start**. It is `claude-prev`'s cost, it only appears on an npm-cache miss (warm is 0.18–0.21 s,
n=11), and three axes measured it independently. Optimising `claude-latest` would have landed a
change that moves `claude` start time by exactly zero.

**C2 — Prior art was blind here for a structural reason, not a careless one.** `R4-cc-latency.md:92`
records `mailbox-drain.sh session-start | 0.02 s ×3`, and R6 puts the whole SessionStart group at
~240 ms. Both harnesses ran hooks under `env -u CC_PANE_ID -u ITERM_SESSION_ID`. That is precisely
the input `mailbox-drain.sh:87` uses to `exit 0`. **The fleet's own hook benchmark has never once
executed this hook's real branch.** Two independent waves recorded 0.02 s and 240 ms for a hook that
takes 15–22 s. This is not a footnote — it is the reason a 4 s regression survived two audits, and
it becomes invariant **I7** below.

**C3 — Two live facts moved between measurement (15:20–16:11) and synthesis (18:2x). Both matter.**

| | at measurement | at synthesis | reading |
| --- | --- | --- | --- |
| reso worktree pool free slots | **0 / 10** | **3 / 10** | the exhausted-pool arm is INTERMITTENT, not permanently armed. The replenisher does heal. So the fix is *visibility*, not a reaper (see S2). |
| `.mcp-probe-cache` age, all four live dirs | 76 / 442 / 2 873 / 44 408 s | **18 454 / 18 471 / 18 532 / 19 334 s** | nothing refreshed any cache for >5 h despite `TTL=300`. A T4 cache whose only refresh trigger is a *new session start* cannot self-heal while the fleet is idle — which is exactly when it ages toward its cliff. |

### 0.1 Red-team pass, 2026-08-16 (adversarial review) — verdict **SHIP-WITH-FIXES**

The diagnosis holds and reproduces. `mailbox-drain` is the dominant cost; it is reaped and throws
its work away; `mailbox_session_is_current` is O(1 300 files) per call; the one-awk-pass fix
**re-measured today at 0.04 s median (n=5, load 18.9, 25 live sessions), 1 296 tips / 1 300 files**.
C1 (`_claude_pinned` does not exist; `_bin=~/.claude-220/…` at `~/.zshrc:496`) and C2 (both prior
waves benchmarked the early-exit guard) are verified and are the most valuable content here.

**Six defects were found and corrected in place. Read these before scheduling anything:**

| # | Where | Defect |
| --- | --- | --- |
| **D1** | §1.1 | `T_turn = 5 716` was presented as validated ("it adds up"). It is circular, and it **splices two harnesses** — T_paint from a REAL dir (paint 1 520 ms), F from a SCRATCH dir (paint ~490 ms). The tell: §5.3 recorded `T_help fresh = 1 402 ms` **below** `T_paint = 1 520 ms`. |
| **D2** | §4 S1 | S1 uncorks an **unbounded** `mailbox_take` into turn-1 context — today's 5 s reap is the only thing preventing it. Violates the doc's own **I2/M5** in its flagship fix. One-line fix. |
| **D3** | §1.1, §2.3 | Post-S1 floor is `setup-task-symlinks` **633 ms**, not `activation-watch` 207 ms (whose in-situ figure is 298 ms, and 207 appears in no axis file). |
| **D4** | §4 S1(b) | The `n++` move is **unnecessary** — red-team measured scan depth median 2 / max 3 and **0.0%** starvation. Dropped; keep emission and scan bounds separate if wanted. |
| **D5** | §4 S1(c) | The `.alias` GC is a **destructive, irreversible** deletion of the liveness oracle's only input, bundled into a LAND-NOW item, with no retention policy. Can cause mail **theft** from a live session. |
| **D6** | §2.3 | The "→ T2" column recovers **0 ms** (all eight hooks are absorbed under paint) while each move relocates cost onto turn 1 — **M1**, the exact regression §3 exists to prevent. Classification only; do not implement. |

**Consequence if uncorrected:** S1 lands, works, delivers its ~4 s — and then **fails 2 of the 5
acceptance gates in §3.3**, because those gates were keyed to scratch-config absolutes and to a
250 ms constant that four hooks already exceed today. The predictable response to a red gate on a
correct fix is to weaken the gate, which is how the next regression gets through.

**Not defects — checked and cleared:** S3's T4 route file adds no staleness (the router already runs
`--max-age 600`, looser than the 180 s keep-warm cadence). Per-invocation memoisation *shrinks* the
liveness-guard race from ~3.6 s to ~40 ms. S1's `CC_MBX_PULL_ADOPT=0` rollback is genuine (it
degrades to today's *effective* behaviour, which is "adopt nothing"). S4/S5 line targets all exist
as cited.

---

## 1. The measured baseline, decomposed

End state definitions, because the two are 4 s apart and conflating them is how the last round went
wrong:

- **T_paint** — the composer is painted and keystrokes echo. What "it started" *looks* like.
- **T_turn** — the input pipeline is free and a submitted prompt actually dispatches. What "it
  started" *is*. Measured zero-token with a local slash command (`/help`), which never touches the
  API, so this is a pure harness measurement.

### 1.1 The table (median, ordinary cwd, real config, REUSED pane — 47.9% of starts)

| # | Layer | ms | % of T_turn | class | how derived |
| --- | --- | ---: | ---: | --- | --- |
| A | zsh entrypoint, pre-exec | 237 | 4.1% | BLOCKING | full chain `claude --version` 386.9 − binary `--version` same flags 150.1 |
| B | binary boot → first byte | 445 | 7.8% | BLOCKING | pty TTFB; real cfg 445 vs empty scratch 490 ⇒ config-independent |
| C | first byte → composer, minimal config | 187 | 3.3% | BLOCKING | 632 (empty-scratch composer) − 445 (TTFB) |
| D | config directory (`showSetupScreens` write stalls 600 + catalogs/parse ~122) | 722 | 12.6% | BLOCKING | ablation: real-minus-MCP 1 365 − scratch 643 |
| E | MCP layer marginal (config resolve 86 + connect residual) | 155 | 2.7% | BLOCKING | real 1 520 − real-minus-MCP 1 365 |
| | **T_paint, binary side** | **1 509** | | | measured 1 520 median (min 1 280, max 1 830) — **residual 11 ms** |
| | **T_paint, from keypress** | **1 746** | | | COMPOSED = A + measured 1 509 |
| F | SessionStart hook group max, past paint | **+3 970** | **69.5%** | **BLOCKING for the turn, 0 ms for paint** | in-situ `/help` A/B 5 424 − 1 410 = 4 014; adversarial pass corrected to 3 970 |
| | **T_turn, from keypress** | **5 716** | 100% | | COMPOSED |

Sum of B–E = 1 509 vs the 1 520 measured on the same instrument ⇒ **the binary-side subtotal is
validated to 11 ms.** That is the only validated composition in this table.

> 🚨 **RED-TEAM CORRECTION (2026-08-16) — T_turn = 5 716 is NOT validated, and this line used to
> claim it was.** The earlier wording ("Sum of A–F = 5 716 = T_turn. It adds up") is circular:
> 5 716 is *defined* as A+…+F, and **no instrument in the evidence base ever measured T_turn on the
> real config**. Worse, F and T_paint come from **two different harnesses with incompatible
> baselines**, so they may not be added:
>
> | | instrument | config dir | composer paints at |
> | --- | --- | --- | ---: |
> | T_paint 1 520 | `measure-statusline-tui.md:195,202` | **real** dir + real reso worktree | **1 520 ms** |
> | F = 5 424 − 1 410 | `measure-sessionstart-hooks.md:310–317` | **scratch** `/tmp/ssprobe/cfg` | **~490 ms** (`:110`, `:146`) |
>
> The tell is visible in §5.3's own baseline list: `T_help p50, fresh = 1 402 ms` is recorded
> **118 ms BELOW** `T_paint p50 = 1 520 ms`. A local slash command cannot render before the composer
> that receives it paints. Two instruments, one list.
>
> **What survives:** F as a *delta* (≈4 s of blocking added by one hook) is sound — a 4 s block is
> 4 s on any config. **What does not:** the absolute 5 716, the "it adds up" validation, and every
> gate keyed to the scratch-arm absolutes (see §3.3). Treat A–F as a **budget model**, not a
> reconciled measurement, until one instrument measures T_turn end-to-end on a real config dir.

**On a FRESH pane (52.1% of starts)** `mailbox-drain` early-exits in 38 ms, the hook group max
becomes ~~`activation-watch` at ~207 ms~~ **`setup-task-symlinks` at 633 ms in situ** (red-team
correction — see D3 at §2.3), that still completes well before the 1 520 ms composer, and **T_turn ≈
T_paint ≈ 1 750 ms**. The 4 s is not a property of starting Claude — it is a property of starting Claude *on a
pane that has held a session before*, which is every `/clear`, every resume, every recycle, every
compact. Measured incidence: **1 198 / 2 502 recorded starts = 47.9%.**

### 1.2 The two tails, which are not in the table because they are not medians

| Tail | magnitude | trigger | state today |
| --- | --- | --- | --- |
| Worktree-pool exhaustion on launch from the reso PRIMARY checkout | **+11 000 to 30 000 ms, silent** — `_cc_route_check` claims a slot, all slots taken, falls through 20 wasted git forks (143 ms) into cold `new-worktree.sh` + `pnpm install --frozen-lockfile` (documented 20–30 s; measured 11–14 s for the install alone). Nothing is printed. | pool 0 free AND cwd = reso primary | intermittent (0/10 at 15:27, 3/10 at 18:2x) |
| MCP `MAX_AGE` cliff | **+2 500 to 3 300 ms BLOCKING** — past `MCP_CACHE_MAX_AGE=86400` `session-start.sh` refuses the cache and shells a second 325 MB Claude CLI inline | a config dir idle >24 h | 21–22% of the way there in all four live dirs; the refresh has not landed in >5 h |

The pool tail may be worse than a wait: slot 7's provisioning has been failing every ensure cycle
with `ERR_PNPM_RECURSIVE_EXEC_FIRST_FAIL … panda ENOENT`. If that failure is repo-wide rather than
slot-local, the cold fallback does not take 20–30 s, it **fails**, `_cc_route_check` returns 1, and
`claude` **refuses to launch** from the primary. UNKNOWN — probe U2 in §8.

### 1.3 What it can be reduced to

| | today | after the plan in §4 | after an upstream fix to `showSetupScreens` |
| --- | ---: | ---: | ---: |
| T_paint (keypress → typable) | 1 746 ms | **~1 610 ms** | ~1 010 ms |
| T_turn, fresh pane | ~1 750 ms | **~1 615 ms** | ~1 015 ms |
| T_turn, reused pane (47.9%) | **5 716 ms** | **~1 615 ms** | ~1 015 ms |
| silent 11–30 s tail | live, invisible | **surfaced and refused, never waited on** | — |
| peer mail delivered into turn 1 on a reused pane | **NO — silently dropped** | yes | yes |

The recoverable, in-our-control total is **~4 100 ms on 47.9% of starts and ~135 ms on the rest**.
The residual ~1.6 s is 60% upstream-owned (Bun boot 112 ms irreducible + `showSetupScreens` 600 ms
unexplained) and 40% config-directory bloat whose ablation delta is measured but whose mechanism is
inside a 195 MB Bun-compiled binary.

---

## 2. The architecture

### 2.1 The principle

> **Boot spends only what the first keystroke is a function of. Everything else is an obligation
> with a deadline and an owner, not a step in a sequence.**

The corollary is the part the last round missed: **deferral is not free, it is a transfer.** It moves
work from a moment the operator expects to wait (the launch) to a moment they expect not to (typing,
submitting). A tier is therefore defined by *what the work is allowed to contend with*, never merely
by *when it runs*. That is why the tiers below carry contention budgets, not just wall-clock budgets.

### 2.2 The tiers

| Tier | Definition | Deadline | Admission rule |
| --- | --- | --- | --- |
| **T0** | The first painted frame is a function of it | ≤600 ms, whole tier | **No fleet code is admissible.** Only binary boot, settings/permission application, config resolve, TUI mount. If fleet code appears here it is a defect by construction. |
| **T1** | Turn 1 would be **wrong** without it — not merely degraded | **≤250 ms group max** | Only "wrong", never "nicer". Exceeding 250 ms is a re-architecture trigger, never a bigger timeout. |
| **T2** | Background, fire-and-forget, needed eventually | no wall-clock deadline; **a contention budget** | Must emit a completion signal (I3) and hold a single-flight lock if it spawns >100 MB or runs >1 s (I4). |
| **T3** | Resident/shared: identical across all sessions AND O(store) | n/a | If cost grows with the store and the answer is the same for every session, per-session execution is an N× tax (I5). |
| **T4** | Precomputed on a schedule, read as a flat file + staleness stamp | read ≤5 ms | Writer is the owning tool, never the reader. A stale/missing file degrades to a **named** default — never to a guess, never to a blocking recomputation (this clause is the anti-cliff rule). |

### 2.3 Every current boot obligation, assigned

**zsh entrypoint layer**

| Obligation | file:line | ms | now | → | Why |
| --- | --- | ---: | --- | --- | --- |
| `claude-accounts --route` | `lib/claude-launcher.zsh:74` | 75 | T0 | **T4** | Pure cache read already; cost is 100% python3 process start (cache-hit 75.2 ms == cache-miss 68.7 ms). The keep-warm agent runs every 180 s and can write the verdict. Abstain (rc=3) must still resolve to PINNED. |
| `cc-close-attrib` exec wrapper | `bin/cc-close-attrib` | 70 | T0 | **T0** (wrapper) + **T4** (its GC) | The wrapper must wrap the exec — it is the only durable stderr capture on the eval track (0 of 52 crash rows carried one before it). But ~30 ms is two `find -mtime` sweeps over 1 348 close-records on **every** launch, collecting litter that accrues daily. |
| `_cc_sync_account` | `lib/config-mirror.zsh:247` | 54 (cross-acct) / 27 (same) | T0 | **T2** | Its own SessionStart twin (`config-mirror-assert`) re-asserts it, and that hook's header says it fixes the NEXT session. Gate the 337-entry walk on a generation stamp. |
| `_cc_tlid` | `~/.zshrc:88` | 22 | T0 | **T0, DECLINED** | 2 git forks for a task-list label. A naive `.git/HEAD` read breaks on detached HEAD, linked worktrees (`.git` is a file) and bare repos, and the failure mode is a *wrong* id — silent mis-filing, not an error. 20 ms is not worth that surface. R3 declined it; so do we. |
| `_cc_route_check` (pool claim) | `lib/claude-launcher.zsh:240` | 8 off-primary / **unbounded on-primary** | T0 | **T2 + refuse-and-print** | A claim that can build a worktree must never sit on the interactive path. |
| `_cc_charge_on_commit` | `~/.zshrc` | 4 | T2 | **T2** | Already correct — 4.3 ms foreground, work in a `&!` subshell after a 5 s settle. The model for the rest. |
| interactive zshrc on a fired pane | `~/.zshrc` (41 KB) | ~200 | T0 for fires, 0 for a live pane | **structural** | `handoff-fire.sh:905` needs `zsh -l -i -c` only because the launcher bodies live in the rc. Move them to PATH scripts and a fire uses `zsh -l -c` (0.02 s). Large change; breaks the `functions[_claude_pinned]=...` snapshot mechanism. Backlog, not now. |

**binary / upstream**

| Obligation | ms | now | → | Why |
| --- | ---: | --- | --- | --- |
| Bun runtime boot + main-module import | 112 | T0 | **T0, irreducible** | 195 MB Bun-compiled Mach-O. `dependencies: {}`. There is no JS entry, so `node --cpu-prof` is structurally inapplicable. No env var, flag or setting touches it. Stop looking. |
| settings + MDM + 981 permission rules | 8 | T0 | **T0** | R4's "~300 ms" was a whole phase (CA certs 73 ms, git remote parse, plugin catalog), not rule compilation. Settings parse is 0.59 ms. Do not trim rules for speed. |
| skills / commands / agents / plugins catalog | 32 | T0 | **T0** | 91 skills. 5× faster than R4's 159 ms. Not a target. |
| CLAUDE.md + rules load | ~9 | T0 | **T0 in ms, DEFECT in tokens** | 12 files / 206 311 chars (~52 K tokens) every start, of which **80 642 chars** load unconditionally because a line-1 markdownlint HTML comment hides the `paths:` frontmatter in six reso rules files. Different currency, real cost. |
| `showSetupScreens()` + 3–4 atomic `.claude.json` rewrites | **600** | T0 | **should be T2, CAUSE UNKNOWN** | Stalls 265–576 ms in an un-logged segment immediately before each write, 3–4× per start. Size-independent (16 KB throwaway paid 279 ms) and contention-independent (fresh /tmp dir, zero peers, 279 ms). A control run with no write completed the same stage in 59–87 ms. **The largest single remaining block, and it is not ours.** |
| MCP config resolve | 86 | T0 | **T0** | The only awaited MCP step, and the log shows it resolves *before* its own await point. Marginal cost bounded 0–86 ms. |
| MCP server connects | concurrent | — | **T1 with an explicit cap** | Batched 3 at a time (`MCP_SERVER_CONNECTION_BATCH_SIZE`, default 3). Concurrent for paint (proven: prompt usable at +0.661 s while ms365 finished at +1.202 s and mac-messages at +1.406 s), but they gate the first turn. |

**SessionStart hooks** (15, identical across five config dirs; group cost = MAX, not SUM — measured
directly: 6 distinct `sleep 3` hooks all start within 6 ms and all end at +3.02 s, moving dispatch
+3.10 s not +18 s)

| Hook | ms in situ | now | → | Why |
| --- | ---: | --- | --- | --- |
| `mailbox-drain` — **own-box take** | — | T1 | **T1** | Peer mail must be in turn 1's context. Non-negotiable, stays synchronous. |
| `mailbox-drain` — **predecessor adoption** | **3 970 (reaped at the 5 s cap)** | T1 | **T2 dispatch, T3 data** | The alias-tip set is a derivation over a 1 300-file shared store; it is identical for every session. Per-session is an N× tax. |
| `session-index-start` context inject | 262 | T1 | **T1** | Must be in turn 1. 41 MB / 3 983-row sqlite is NOT the cost (the lead's prime suspect is refuted); the blocking half is one python3 boot + an indexed query. |
| `desk-brief-inject` | 37 | T1 | **T1** | It *is* turn-1 context. |
| `activation-watch` | ~~129–207~~ **298 in situ** | T2 | **T2** | ~~After S1 this becomes the group MAX~~ — **WRONG, see D3.** It is not even the second-largest. |
| `setup-task-symlinks` (active list) | 633 | T2 | **T2** | Already rewritten 21 s → 237 ms (R6, holds). Residual is the ACTIVE list's TASKS.md regeneration. |
| `setup-task-symlinks --sweep` (2 578 dirs) | detached | T2 | **T3** | O(store), fleet-identical, already 600 s-throttled on a **fleet-shared** stamp — correct as shipped; formally a T3 obligation being run by whichever session happens to be first. |
| `session-start.sh` MCP line | 69–88 warm | T4 | **T4** | SWR is correct and holds (2.52 s → 0.036 s). Only its `MAX_AGE` fallback violates the T4 rule. |
| `pre-session-validate` | 333 | T2 | **T2 + T4 stamp** | Can only ever fix the NEXT launch (the binary under test is already running). A per-version stamp skips it entirely. |
| `config-mirror-assert` | 224 | T2 | **T2** | Its own header: "fixes the NEXT session, not the running one." Deferrable with zero semantic loss. |
| `setup-plan-symlinks` | 75 | T2 | **T2** | — |
| `lead-crash-watchdog` | 52–64 | T2 | **T2** | — |
| `frontier-status` | 60–63 | T2 | **T2** | — |
| `session-register` / `live-session-registry` | 87 | T2 | **T2** (T3 candidate) | A registry write is a shared-store write; fine at 87 ms, but it is the shape that belongs to a daemon. |
| `dod-persist` | — | T2 | **T2** | Scope is read at close, not turn 1. |
| `mailbox-wake-arm` (`timeout: 14400`) | **0** | T2 | **T2, exemplary** | `asyncRewake: true` is honoured; the harness dispatches it in the background. A synthetic 6 s async hook left `/help` at 1.399 s. **This is what a correct T2 looks like — copy it.** |

> 🚨 **RED-TEAM CORRECTIONS TO §2.3 (2026-08-16).**
>
> **D3 — the post-S1 floor is `setup-task-symlinks` at 633 ms, not `activation-watch` at 207 ms.**
> Two errors compounded. First, `activation-watch`'s in-situ cost is **298 ms**
> (`measure-sessionstart-hooks.md` PART C); 129 ms is its *isolated* B1 figure and 207 ms appears in
> no axis file at all. Second, the same table this row sits in already lists
> `setup-task-symlinks` at **633 ms**, `pre-session-validate` at **333 ms** and
> `session-index-start` at **262 ms** — all in the same group, all larger. Since group cost = MAX,
> the post-S1 floor is **633 ms**, ~3× the number stated, and four hooks exceed the ≤250 ms gate in
> §3.3 **today, before any change** (see the §3.3 correction). The headline conclusion survives
> unharmed — 633 ms is still fully absorbed under a 1 520 ms paint — but the floor figure and the
> gate keyed to it do not.
>
> **D6 — the "→" column is a CLASSIFICATION, not a worklist; implementing it recovers 0 ms and
> re-creates the regression §3 exists to prevent.** Eight hooks are marked "→ **T2**". Because group
> cost is MAX and the composer paints at 1 520 ms, every one of them is **already absorbed**: the
> axis doc says so outright — *"together they measure 0 ms of blocking cost"*. Moving them to T2
> therefore recovers **nothing**, while each move converts an absorbed, pre-paint obligation into a
> post-paint contender for turn 1 — **M1**, verbatim, and the operator's 2026-08-11 complaint. §4
> correctly proposes no such move (S1–S12 defer no hook but mailbox-drain). **Mark the column
> read-only so a future session does not implement it:** the only hook whose tier change is worth
> anything is `mailbox-drain`, because it is the only one not absorbed.

**post-paint surfaces**

| Obligation | ms | class | Verdict |
| --- | ---: | --- | --- |
| `statusline.sh` | 48.6 / render @ 0.03 Hz | CONCURRENT | **Exonerated twice over.** First paints 130–860 ms AFTER the composer; fleet-wide load is 0.55% of one core. Leave it. Budget rule for the future: ≤50 ms and ≤0.1 Hz, else demote to T3 (a daemon writes a line, the statusline `cat`s it). |
| `remoteControlAtStartup` | 925.6 (n=34: min 632.9, p75 1 152.6) | CONCURRENT | **0 recoverable ms and PROVEN UNMEASURABLE to ablate** — a copied config dir reports "Not logged in" (credentials live in the Keychain), so remote control never activates in any scratch arm. Leave it on. |

---

## 3. The anti-regression contract

The previous round bought paint time and paid in felt lag. That is not a risk to be careful about,
it is a mechanism with five named forms. Every one of them is present in today's evidence.

### 3.1 How deferral converts into felt lag

**M1 — The turn, not the paint, is where deferred work lands.** SessionStart hooks are CONCURRENT
for paint and BLOCKING for the turn. Directly measured: six `sleep 3` hooks moved time-to-composer
by **0 ms** and moved first-turn dispatch by **+3.10 s**. So "we moved it off the paint path" is not
"we made it free" — it relocated the cost to the exact moment the operator submits, which reads as
*the box is up and nothing is happening*. That is the 2026-08-11 complaint verbatim.

**M2 — A detached heavyweight contends with the first turn.** `session-start.sh`'s SWR costs the
hook 69 ms and detaches a **325–329 MB** second Claude CLI that connects 6 MCP servers and runs
1.2–3.3 s (cold tail measured 31.6 s). On a box at load 19 that competes with turn 1. The deferral is
still correct — but it is correct *because* it is bounded (below), not because it is detached.

**M3 — Thundering herd.** Any T2 job keyed on session start multiplies by concurrent starts, and a
wave fire starts 6–10 sessions in seconds. The bound must be **structural**, not statistical: the
adversarial pass proved `_mcp_spawn_refresh`'s atomic `mkdir` test-and-set holds 8 concurrent
SessionStarts in one config dir to **exactly 1** refresher. Herd bounded at 5 box-wide (one per dir).
Copy that idiom; do not invent a new one.

**M4 — The re-blocking cliff.** A T4 cache with a `MAX_AGE` that falls back to inline recomputation
converts, silently and with no commit, back into the blocking cost it replaced. Today all four live
`.mcp-probe-cache` files are 5.1–5.4 h old against a 300 s TTL, 21% of the way to an 86 400 s cliff,
and nothing has refreshed them — because the only refresh trigger is a new session start, i.e. the
cache cannot heal during precisely the idleness that ages it.

**M5 — Capped-and-discarded, the worst shape and the one that actually happened.** `mailbox-drain`
is reaped at its 5 s timeout: it pays the **full** latency **and** throws the work away, so peer mail
is silently dropped at every session start on a reused pane. A timeout without a degraded result is
strictly worse than the blocking version it replaced. The code even carries the invariant it
violates — `mailbox-pending.sh` comments "a hook must never do unbounded work (R3)" directly above a
loop whose `n=$((n+1))` sits *after* the `mailbox_session_is_current && continue`, so the bound
counts **emissions**, not **candidates**, and a trail of live sessions is unbounded (max observed
trail: 71).

### 3.2 The invariants

- **I1 — Tier by deadline, not by convenience.** Every boot obligation declares a tier and a
  deadline. T1's group deadline is **250 ms**. A T1 obligation that exceeds it is a defect; raising
  its `timeout` is forbidden as a remedy.
- **I2 — No unbounded work on any interactive path, and every cap has a named degraded result.** A
  cap without a degradation is a silent drop (M5). Bound the *input* (candidates scanned, files
  walked), not only the *output*.
- **I3 — Every deferral emits a completion signal.** A T2 job that is killed, fails, or never
  dispatches must be observable. Today mailbox-drain's reap is invisible and four MCP refreshes have
  silently not landed for 5 h. Concretely: T2 jobs write `{job, started, ended, rc}` to a stamp and
  `wrap-ledger.sh` surfaces `T2 overdue: <job>` at close.
- **I4 — Contention budget, not just a wall-clock budget.** A T2 job is charged CPU-seconds ×
  concurrency. Any T2 job spawning >100 MB or running >1 s must hold an atomic-`mkdir` single-flight
  lock, scoped as widely as the work is identical (fleet-wide where fleet-identical, not per-dir).
- **I5 — O(store) work is T3, never per-session.** If cost grows with the store (1 300 alias files,
  2 578 task dirs, 3 983 sessions, 487 project entries) and the result is identical across sessions,
  per-session execution is an N× tax that grows monotonically and crosses its timeout **silently on
  an unknown date**. That is exactly what happened to mailbox-drain.
- **I6 — The acceptance measurement is T_turn, not T_paint.** No change lands without both numbers,
  and T_turn may not regress. A design that optimises paint and pessimises the first turn has failed,
  by definition, whatever the paint number says.
- **I7 — Never benchmark a hook with its own early-exit guard tripped.** Supply a realistic pane id
  and, for the reused-pane arm, a realistic predecessor trail; then **assert the hook took its real
  branch** (a branch marker in its log, or an assertion that the measured time is not the guard
  time). Two prior waves recorded 0.02 s and 240 ms for a 15–22 s hook because they did not. This
  invariant is worth more than any individual fix in §4.

### 3.3 The acceptance measurement

A startup change is accepted only against **all five**, run by the instrument in §5:

| Gate | Threshold | Rationale |
| --- | --- | --- |
| `T_paint` p50 | ≤1 800 ms | today 1 746 (composed) / 1 520 (binary side) |
| **`T_help_render − T_help_typed`, REUSED arm** | **≤250 ms** | **the input-pipeline gate** (revised — see below). **This is the one that would have caught mailbox-drain**: today it reads **5 134 ms** (`measure-sessionstart-hooks.md:111–113`, typed 1.368 → rendered 6.502) against 13 ms on the fast arm. |
| `hook_group_max`, both arms | **≤ measured `T_paint` on the same run** (absorbed), and ≤250 ms only for hooks that are *not* absorbed | I1, corrected — see below |
| hooks reaped by timeout | **0** | rc≠124 and no truncation marker (I2/M5) |
| T4 cache age / TTL, all dirs | <3× | the cliff detector (M4) |

> 🚨 **RED-TEAM CORRECTION (2026-08-16) — two of these five gates were unpassable as originally
> written, and S1 would have been recorded as a FAILURE on landing.**
>
> **(a) `T_help ≤1 600 ms` absolute was keyed to the wrong arm and to a harness constant.** The
> 5 424 / 1 410 pair was measured on a **scratch** config dir (see §1.1 correction). The doc's own
> ablation prices a real dir at **+722 ms** (layer D: `cfg-rcon` 643.6 → real tertiary 1 365.1,
> `measure-statusline-tui.md:234,237`) plus layer E 155 ms. So on a real config, today's reused-arm
> number is ≈ **6 150 ms**, not 5 424 — and the *post-S1* number is ≈ 1 450 + 722 ≈ **2 170 ms**,
> which **fails the ≤1 600 ms gate it was written to pass**. Second defect in the same number: the
> pty harness types at a hardcoded `PROBE_TYPE_AT=1.2`, so ~85% of the 1 410 ms "floor" is the
> probe's own sleep. An absolute threshold in that unit measures the harness.
> **Fix applied:** gate the **delta** `render − typed`. It is instrument-independent, config-dir
> independent, immune to `PROBE_TYPE_AT`, and the hook axis already emits both timestamps.
>
> **(b) `hook_group_max ≤250 ms` fails TODAY on four hooks, before any change.** In-situ
> (`measure-sessionstart-hooks.md` PART C): `setup-task-symlinks` **633**, `pre-session-validate`
> **333**, `activation-watch` **298**, `session-index-start` **262**. A gate that is red on day one
> on both arms gets weakened or muted, and then the real regression walks through it — the precise
> failure I1 exists to prevent. The operative fact is that on a real config the composer paints at
> 1 520 ms, so **any hook group under ~1 500 ms is absorbed and costs the operator nothing**;
> §1.1's own logic says so. Gate absorption, not an arbitrary constant.

---

## 4. Implementation plan

Ranked by (measured ms recovered) ÷ (risk × effort). "Land now" = inside the auto-continue envelope
with a verified kill switch; "operator's call" = a value judgement or an escalation surface.

### S1 — `mailbox_session_is_current`: hoist the tip set, bound the candidates — **3 970 ms on 47.9% of starts. LAND NOW.**

- **Where:** `hooks/lib/mailbox-pending.sh:548` (`mailbox_session_is_current`), reached from
  `hooks/mailbox-drain.sh:243` (`mailbox_adoptable_predecessors`).
- **What:** (a) the function re-derives the entire tip set on **every** call by looping all 1 300
  files in `~/.claude/mailbox/.alias` with `tail -n1 | awk` — 2 forks/file, 2 600 forks per call,
  ~3.6 s per call, ~3 calls per invocation. Compute the tip set **once per hook invocation** with a
  single awk pass and memoise it in a shell var: `awk 'FNR==1{if(NR>1)print p} {p=$2} END{print p}'
  ~/.claude/mailbox/.alias/* | sort -u` measures **0.03–0.04 s for all 1 300 files** — ~100×.
  ✅ **Re-measured 2026-08-16 by the red-team pass, n=5, load 18.9, 25 live sessions: 0.04 s median
  (0.23 s cold first run), 1 296 tips over 1 300 files. (a) reproduces exactly and is the sound core
  of this document.**
  (b) ~~Move `n=$((n+1))` so the bound counts **candidates scanned**~~ — **DROPPED, see D4 below.**
  (c) GC `.alias`: 1 300 files spanning Jul 29 → Aug 16, monotonic, nothing prunes it — **DO NOT
  LAND WITH S1; see D5 below for the one constraint that makes it safe.**
  (d) **NEW, REQUIRED: bound the adopted payload.** `mailbox-drain.sh:~243` surfaces adopted mail
  with `mailbox_take "$own_uuid" 0` — and `mailbox_take` is **unbounded** (`mailbox-pending.sh:303`
  → `mailbox_take_n "$1" "$2" 0`, where the trailing `0` is *max=unlimited*; the `0` at the call
  site is `ack_now`, not a cap). See D2.
- **Recovers:** 3 970 ms of first-turn latency on 1 198 / 2 502 starts — **and the hook completes**,
  so peer mail stops being silently dropped. The correctness win is the larger one.
- **Verify:** hook probe with a real pane id and a ≥2-entry trail; assert wall ≤250 ms, rc=0, `.seen`
  advanced, and the adoption branch was *taken* (I7). Then the in-situ `/help` A/B: 5 424 → ≤1 450 ms.
- **Roll back:** `CC_MBX_PULL_ADOPT=0` — verified 158× rollback (11.04 s → 0.07 s), already wired at
  `mailbox-drain.sh:221`. Plus `git revert`.
- **Risk:** low-medium. The adoption guard is load-bearing (it refuses to steal from a session that
  resumed elsewhere); memoisation must be per-invocation, never persisted across invocations.
  ✅ Red-team note in S1's favour: per-invocation memoisation **shrinks** the guard's staleness
  window rather than widening it. The current loop is not atomic and takes ~3.6 s, so a session
  claiming a pane mid-scan is already missed for up to 3.6 s; one awk pass cuts that to ~40 ms.

> 🚨 **RED-TEAM CORRECTIONS TO S1 (2026-08-16).** (a) is sound and reproduces. Three of the four
> sub-items around it are not ready to land as written.
>
> **D2 — S1 uncorks an UNBOUNDED take into turn-1 context, and today's 5 s reap is the only thing
> preventing it.** Adoption currently never completes (killed mid-`mailbox_adoptable_predecessors`),
> so `mailbox_take` never runs. S1 makes it run — on 47.9% of starts. The primitive it calls is
> unbounded, while the codebase already ships the bounded one **for exactly this reason**:
> `mailbox_take_n`'s own header (`mailbox-pending.sh:307–316`) says *"a 600-line box must not be
> dumped into a tool result"* and *"advances the cursor by EXACTLY what it printed — never by the
> window it could have taken … whatever is left over is not lost."*
> **Measured exposure today** (red-team, read-only): 1 296 current tips / 1 165 adoptable
> non-current sessions / **14 adoptable boxes holding pending mail, 23 lines, 9 464 chars (~2.4 K
> tokens); largest single adoptable box 7 lines / 5 446 chars (~1.4 K tokens)**. So this is a
> **structural** hazard, not a live fire — but the store is unpruned and monotonic (the largest box
> in the mailbox overall holds **8 294 pending lines / 2.26 MB / ~566 K tokens**; it is not in an
> alias trail *today*, and nothing stops one being tomorrow).
> **Fix (one line, zero correctness cost):** call
> `mailbox_take_n "$own_uuid" 0 "${CC_MBX_ADOPT_MAX_LINES:-200}"`. The remainder is not dropped —
> it is still `(seen, EOF]` and the next boundary takes it. Without this, S1 satisfies its latency
> claim while violating **I2** ("bound the input… every cap has a named degraded result") and
> re-creating **M5** in the very fix that names M5 as the worst shape.
>
> **D4 — (b) is unnecessary and carries a real starvation mode for zero measured benefit; DROPPED.**
> The hypothesis was that moving `n=$((n+1))` above `mailbox_session_is_current && continue` starves
> adoption, because alive predecessors near the trail tip would eat the `max=3` budget. **Red-team
> measured it and the hypothesis is REFUTED for today's store:** across 488 panes with ≥1 candidate,
> scan-depth-to-emit-3 is **median 2, max 3**, and **0.0% of panes would emit zero** under the
> candidate-bounded form. But the benefit is also zero — max scan depth is already 3, and after (a)
> each check is a hash lookup, so there is nothing left to bound. It changes a bound whose semantics
> the code documents ("the bound keeps the MOST RECENT predecessors") to buy nothing.
> **If a scan bound is still wanted for I2 hygiene, keep them SEPARATE**: leave `max` counting
> emissions and add `CC_MBX_ALIAS_MAX_SCAN` (default ≥25) counting candidates. Do not overload one
> counter with both meanings.
>
> **D5 — (c) is a destructive, irreversible deletion bundled into a LAND-NOW item, and it can cause
> mail THEFT.** `.alias` is not litter: it is the sole input to `mailbox_alias_trail` **and** to
> `mailbox_session_is_current`, i.e. the liveness oracle. Delete the alias file for pane P and P's
> live session vanishes from the tip set; if that session appears in another pane's trail, the guard
> now reports it dead and its mail is adopted out from under it — the exact theft the guard exists to
> prevent. S1(c) specifies **no retention policy, no dry-run, no kill switch**, and mtime is not a
> safe proxy (a long-lived session's alias file is only touched at boundaries, so it ages while
> live). Registry cross-check is not sufficient either — the registry knows **13** sessions against
> **25** live processes.
> **Measured exposure today:** 846 files >7 d, 380 >14 d, 32 touched in 24 h, and **0** files >7 d
> whose tip is a live registered session — so an age-based prune is *currently* safe, which is
> exactly how this lands unnoticed and bites later.
> **Fix:** split (c) out of S1 into its own operator-visible change, and make the rule
> **"never delete an alias file whose tip is in the current tip set, at any age."** That set is
> already computed by (a), so the constraint is free and makes the GC provably theft-free.

### S2 — Worktree-pool: refuse-and-print, then decide on a reaper — **removes an 11–30 s silent tail. HALF LANDS NOW.**

- **Where:** `lib/claude-launcher.zsh:240` → `~/.reso/bin/worktree-pool.sh` `cmd_claim` cold fallback.
- **What (land now):** make the cold fallback **REFUSE and PRINT the repair command** instead of
  silently building a worktree with `pnpm install` on the interactive launch path. The operator then
  chooses, instead of staring at a blank prompt for 20–30 s.
- **What (operator's call):** a reaper that releases slots whose recorded PID is gone AND the tree is
  clean. **Deprioritised by live evidence** — the pool healed from 0/10 to 3/10 in three hours
  unaided, so the replenisher works and a reaper is a second mechanism competing with it. Reaping a
  slot whose session is merely idle pulls a worktree out from under a live session.
- **Also:** repair slot 7's `panda ENOENT` so `ensure` can self-heal (see U2 — this may be repo-wide,
  in which case the cold fallback does not slow the launch, it **breaks** it).
- **Verify:** `worktree-pool.sh status`; force-exhaust a scratch copy and assert the refuse path
  prints and returns non-zero in <200 ms.
- **Risk:** the refuse path converts an eventual success into an error. That is the intended trade,
  and it requires the printed repair command alongside it.

### S3 — Route verdict → T4 flat file — **75 ms on 100% of launches. LAND NOW.**

- **Where:** `lib/claude-launcher.zsh:74`.
- **What:** the decision is already a pure cache read; the entire 75 ms is python3 process start
  (proven: cache-hit 75.2 ms ≈ cache-miss 68.7 ms). Have `claude-accounts` **itself** emit the
  verdict + a staleness stamp at sweep time (the keep-warm agent runs every 180 s); the launcher
  reads with zsh `$(<file)` and forks only when the stamp is stale.
- **Verify:** `bench "route-file" 7` → ≤3 ms; with the file deleted, assert rc=3 abstain still yields
  **PINNED**, never a guessed account.
- **Roll back:** `CC_ROUTE_FILE=0` → the fork path, unchanged.
- **Risk:** two readers of one decision is the second-truth the script's own header warns about.
  Mitigated absolutely by one rule: **the file is written only by `claude-accounts`, never by the
  shell.** Fail to PINNED on missing or corrupt.

### S4 — `cc-close-attrib`: gate the two `find -mtime` sweeps behind a daily stamp — **30 ms on 100% of launches. LAND NOW.**

- **Where:** `bin/cc-close-attrib:74`.
- **What:** two `find "$RECORDS_DIR" -maxdepth 1 -type f -mtime … -delete` sweeps run on every launch
  over **1 348 files / 5.0 MB** to collect litter that accrues daily. Copy the file's own idiom from
  two blocks lower (`[[ ! -e "$VER_CACHE" ]] || find "$VER_CACHE" -mtime +1`).
- **Verify:** n=8 wrapped-vs-raw A/B → 0.14 s median should become ~0.11 s.
- **Roll back:** `CC_CLOSE_ATTRIB_DISABLED=1` (exists) or revert. The file is fail-open by design.
- **Do NOT touch:** the FIFO/tee spelling or the wait-then-test ordering. Both are documented fixes
  for measured incidents (the load-781 lingering-tee leak; an exit-code misattribution that wrote
  `"exit_code":0` for real crashes).

### S5 — `_cc_sync_account` generation stamp — **54 ms cross-account (the live case). LAND NOW.**

- **Where:** `lib/config-mirror.zsh:247`, called `~/.zshrc:479`.
- **What:** skip the 337-entry walk and the dangling-link reap when `~/.claude`'s mtime + entry count
  are unchanged since the last successful sync **for that destination**. Routing picks a cross-account
  dir today, so the live launch pays 54 ms, not 27.
- **Risk:** a stale mirror degrades silently rather than erroring, and a symlink retargeted in place
  with unchanged mtime would be missed. Blast radius capped: `config-mirror-assert` re-asserts at
  SessionStart. Smallest payoff of the shell items; land it last of the four.

### S6 — `MCP_CONNECTION_NONBLOCKING=1` as a **tail guard** — **0 ms typical. OPERATOR'S CALL.**

Measured gain on the real 4-server set is **zero** (0.844 s → 0.890 s) because no real server exceeds
the ~2.0 s pre-wait cap. Its value is insurance: it caps a hung or cold-`npx` server (first-touch
1.94 s vs 0.84 s warm) instead of letting the batch-of-3 gate turn 1. Cost: a first prompt calling an
MCP tool could see "tool not found". This is a semantics change for a 0 ms median win — the
operator's call, not an auto-land. Better structural alternative for the same tail: pin `ms365` to a
resolved absolute path instead of `npx` (three of five dirs already do; the legacy `~/.claude.json`
does not).

### S7 — Remove `mac-messages` — **0 ms. 18 processes / 650 MB physical. LAND NOW (as a memory fix, banking 0 ms).**

Refuted as a latency item: median connect 353–362 ms (not 1 120), and removing it moved
time-to-usable-prompt **+14 ms** — i.e. nominally *slower* without it, which is noise. What survives
and is *understated*: 9 process pairs / 486 MB RSS but **650 MB physical footprint** (`vmmap`, median
69 MB/pair — RSS lies here because idle pairs swap out), for **0 invocations across 7 196 transcripts
all time**. Use `claude mcp remove mac-messages` per dir — **never a hand-edit**: `.claude.json` is
rewritten in place by live sessions (two were rewritten within 6 minutes during the wave), so a
hand-edit gets clobbered or clobbers session state. Note `~/.claude` is inert here (its
`.claude.json` has no `mac-messages` and no live session uses that dir) — three dirs, not four.

### S8 — `ms365` → opt-in — **0 ms. 15 procs / 1 346 MB / 188 tool definitions / 0.24% use. OPERATOR'S CALL.**

Refuted as latency: the arm **with** ms365 painted 7 ms **faster** than without, and in 6/6
instrumented boots ms365 never completed its connect at all while paint was unaffected — a total
connect failure costs 0 ms, which is the hard ceiling on what removing it could recover. The
sub-claim "RSS grows with session age" is affirmatively **wrong**: the five oldest processes
(16–18 h) are the *smallest* at 45–46 MB while the largest (144–145 MB) are ~3 h old. RSS tracks
**use**, not age. Real cost is discoverability vs 1.3 GB; that is a judgement, not a measurement.

### S9 — Move the line-1 markdownlint comment below the frontmatter in six reso rules files — **0 ms, ~20 K tokens/session. OPERATOR'S CALL.**

`.claude/rules/{replicache,view-transitions,monitoring,bottle-service,migrations,api-security}.md:1`.
The HTML comment on line 1 hides the `paths:` frontmatter from the loader, so **80 642 chars load
unconditionally** while reading as conditional. Positive/negative control: the only two rules files
with frontmatter on line 1 are the only two the binary does *not* enumerate. Verify by relaunching in
a cwd touching none of those paths: `Loaded 12 CLAUDE.md/rules files … 206 311 chars` should become
6 files / 125 669 chars. **Risk is the inverse of the defect** — once scoping works, sessions that
today silently rely on always-resident `replicache.md` will stop having it. Confirm each file's
`paths:` globs are correct *before* unhiding them.

### S10 — `showSetupScreens()` (600 ms) — **DO NOT ACT. DIAGNOSE FIRST.**

Two hypotheses are already refuted by measurement (file size; cross-session lock contention), so do
**not** "fix" it by shrinking `.claude.json` or sharding config dirs. Largest single remaining block;
upstream-owned; cause UNKNOWN. Probe U1 in §8.

### S11 — `.claude.json` prune (368–487 dead `projects` entries) — **~0 ms. OPERATOR'S CALL, hygiene only.**

Parse is 1.3 ms and measurably size-independent, so **do not promise ms**. The reasons are that the
file is rewritten 3–4× per start with fsync, and that it grows +324 B per launch with nothing pruning
it. Prune **only** entries whose directory no longer exists — dropping one drops
`hasTrustDialogAccepted`, and a re-visited path then shows a trust dialog that **blocks a spawned
pane forever**. Quiesce the fleet or use the CLI; never hand-edit under 28 live sessions.

### S12 — `claude-latest`'s unhittable version cache — **0 ms on the `claude` path. LAND NOW (fallback-track hygiene).**

`~/bin/claude-latest:169` compares `cached_version` (which line 176 sets to what **npm** returned,
2.1.233) against `installed` (pinned 2.1.114 by MANIFEST default-deny), so the equality clause can
**never** hold and `CACHE_TTL=600` is dead code — every `claude-prev` launch makes a blocking
`timeout 3 npm view` (measured 0.39–1.13 s, worst case a hard 3 s on a degraded link). Perversely,
only a **failed** network call ever writes a hittable cache, via the `|| echo "$installed"` fallback.
One-line fix: let `cache_age < CACHE_TTL` alone gate. **Do not sell this as a cold-start win** — it
is off the `claude` path entirely (C1). Bundle the fork-per-file `basename` in the stderr GC at
`:373` while in there (124 ms today at 41 files, 588 ms at the block's own 200-file cap; pure
parameter expansion removes both).

---

## 5. The permanent instrument

Two probes and one guard, committed, so this is never re-litigated from memory.

### 5.1 `scripts/boot-latency-probe.py` — zero-token pty harness

**Measures**, per run: `T_first_byte`, `T_composer`, `T_echo(offset)`, `T_help` (a local slash
command — the input-pipeline gate, and the number that matters), and optionally `T_dispatch` via a
**local API recorder** (`ANTHROPIC_BASE_URL=http://127.0.0.1:<port>`) so first-turn dispatch is
measured at **zero quota cost**. Emits JSON: `{arm, pane_mode, n, min, p50, p75, max, loadavg,
live_sessions, binary, config_dir}`.

**Five design rules, each earned by a bug that produced a confident null in this wave:**

1. **ANSI-strip and accumulate before matching a marker.** The wave's first harness matched
   per-read-chunk and never saw the composer footer, because the TUI interleaves cursor escapes
   between words. It reported a clean null.
2. **Supply a realistic pane and assert the branch (I7).** `--pane fresh|reused`; the reused arm
   seeds a predecessor alias trail in a **copy** of the mailbox (`CC_MAILBOX_DIR`), and the run
   **fails** if the measured hook time equals the guard time.
3. **Interleave arms, never batch them.** At load 19 a batched arm measures the load, not the change.
   n≥7, alternating, report min *and* median (min is the robust statistic here).
4. **Record `loadavg` and live-session count with every sample.** A number without its load is not
   comparable to another number.
5. **Use the binary's own profiler for attribution.** `CLAUDE_CODE_PROFILE_STARTUP=1` writes a
   48-checkpoint report to `$CLAUDE_CONFIG_DIR/startup-perf/<sid>.txt` (undocumented, first-party,
   free). Two gotchas: it does **not** fire on `--version`, and the file is flushed on the way out,
   so wait ~2 s after SIGINT or you read "NO REPORT". Pair with
   `CLAUDE_CODE_SLOW_OPERATION_THRESHOLD_MS=<ms>` to surface slow sync FS/JSON ops.

**Safety:** ablation arms use a throwaway `CLAUDE_CONFIG_DIR` under the scratchpad; the truth arm
uses a real dir **read-only**; SIGINT before any prompt is submitted; never writes a live config.

### 5.2 `scripts/hook-latency-probe.sh` — per-hook timing that cannot lie

Runs each SessionStart hook with a **real** payload on stdin, a **real-shaped** `ITERM_SESSION_ID`, a
throwaway `CLAUDE_CONFIG_DIR`, and a **copy** of the mailbox. Emits per-hook wall time **and the
group MAX** — the only number with operational meaning, since the group cost is MAX not SUM. Asserts
per hook: `rc != 124` (not reaped) and `branch_taken != guard`.

### 5.3 `scripts/boot-latency-guard.sh` — the regression guard

Runs from the existing background `postland-verify` (or a launchd timer), asserts the §3.3 gates
against the baselines recorded below, and writes one line into the store `wrap-ledger.sh` reads, so a
breach is visible at close rather than felt three weeks later.

**Baselines to record on first commit** (2026-08-16, load 14–24, ~24–28 live sessions).
🚨 **RED-TEAM CORRECTION — every baseline now carries its INSTRUMENT, because the original list
mixed two and the mix was invisible.** A guard seeded from two instruments either never fires or
always does. **Numbers from different rows may not be subtracted from one another.**

| Baseline | Value | Instrument / config dir |
| --- | ---: | --- |
| `T_paint p50` (binary side) | 1 520 ms | `measure-statusline-tui.md:195` — **REAL** dir + real reso worktree |
| `T_help p50, fresh` | 1 402 ms | `measure-sessionstart-hooks.md:310` — **SCRATCH** `/tmp/ssprobe/cfg`, paint ~490 ms, types at `PROBE_TYPE_AT=1.2` |
| `T_help p50, reused` | 5 424 ms | same SCRATCH instrument (**pre-fix; the guard's first job is to prove S1 moved it**) |
| **`T_help_render − T_help_typed`, fresh** | **13 ms** | the gate metric (§3.3) — instrument-independent |
| **`T_help_render − T_help_typed`, reused** | **5 134 ms** | the gate metric (§3.3) — **this is the number S1 must move** |
| `hook_group_max, fresh` | ~~207~~ **633 ms** | in-situ PART C (`setup-task-symlinks`) — see D3 |
| `hook_group_max, reused` | 5 000 ms (reaped) | in-situ |
| `shell layer` | 237 ms | `measure-shell-fn.md` — ⚠️ **not re-measurable safely**: the full-chain arm runs `_cc_sync_account` (writes the live config mirror) and `_cc_route_check` (can claim a pool slot). Re-derive from components, never by timing `claude --version` through the live function. |
| `statusline render` | 48.6 ms @ 0.03 Hz | `measure-statusline-tui.md` |

**Two baselines the guard must also record but nobody has measured:** `T_help` on a **real** config
dir (every `T_help` above is scratch — the real-dir number is ≈ +722 ms by layer D, §3.3(a)), and
`T_help` under **live mailbox flock contention** (U5 — every 15–22 s and 3 970 ms figure was taken
against a *copy* of the mailbox, deliberately excluding it, so the post-fix residual has an
acknowledged and un-propagated error term in the *unsafe* direction).

---

## 6. Ruled out, and why

Five hypotheses did not survive the adversarial pass. Each is recorded because *not* spending effort
here is worth as much as the fixes above — and because each has an obvious re-litigation risk.

| Ruled out | Claimed | Actual | Why it looked true |
| --- | --- | --- | --- |
| **`~/bin/claude-latest` costs ~1.3 s of every launch** | 1 300 ms BLOCKING | **0 ms** — not on the `claude` path at all (C1); and the 1.3 s is the npm cache-**miss** path (warm 0.18–0.21 s, n=11) | The timing replicates perfectly. The inference does not: **no session runs that command.** Today's log entries "proving" it runs are the measurement probes themselves — the instrument created the evidence for its own premise. |
| ~~**`session-start.sh` SWR detaching a second CLI is a hotspot** (3 974 ms)~~ **← OVERTURNED, see R1 below** | 3 974 ms | ~~Hook returns in **69 ms** with the refresh lock still held~~ — true of the PROCESS, false of the PIPE | ~~3 974 ms is a real wall-clock — of a process **nothing blocks on**.~~ Something does block on it: the harness. **Keep the SWR** — that half stands. |
| **`session-start.sh` cold/`MAX_AGE` inline probe** (2 655 ms) | 2 655 ms BLOCKING | Number **reproduced** (2 513–2 672 ms) but the branch is reachable ~once per config dir per >24 h idle spell ⇒ **~10 ms/start amortised**, and warm it contributes **0 ms** because `activation-watch` (~207 ms) is the group max | The code reading is correct; only the ranking is wrong. Fix the **semantics** as a T4 invariant (M4), not for milliseconds — and note the proposed "serve UNKNOWN" must still detach a probe, or a first-ever dir gets a permanently blind sensor, which the hook's own header rejects in writing. |
| **`mac-messages` costs 1 120 ms** | 1 120 ms | median **353–362 ms** (n=13, max 903–949); removing it moved time-to-usable-prompt **+14 ms** | One sample from a 4-way simultaneous spawn at load ~24. The last-connect in a 5-server config is **uidotsh** (492–2 296 ms), never mac-messages. Memory finding survives and is understated. |
| **`ms365` costs 971 ms** | 971 ms | **0 ms** — the arm *with* ms365 was 7 ms **faster**; and in 6/6 instrumented boots ms365 **never completed** its connect while paint was unaffected | Even in the original run, `mac-messages` (1 120 ms) was the group max in the *same* run — under max-of-parallel its marginal cost was already 0 before anyone re-measured. |

Two hypotheses **survived** verification: `mailbox-drain` (3 970 ms, BLOCKING, corrected down from
5 000 and re-classed from "blocks the input pipeline" to the more precise "blocks turn dispatch") and
`remoteControlAtStartup` (925.6 ms, CONCURRENT, **0 recoverable**, and its original proof was
invalid — `/rc connecting…` is the widget's not-connected label painted in the composer's own first
frame, measured 0.0 ms after the composer in 22/30 runs, so "the marker never precedes the composer"
is a test that cannot fail. The sound argument is different and stronger: the first frame renders the
widget *not connected*, so the dial is demonstrably not awaited).

---

## 7. Prior-art status

**Still holds** — SessionStart hooks block (now sharpened: they block the **turn**, not the paint) ·
hook group cost = MAX not SUM (now direct, not inferred) · MCP connects are parallel and non-blocking
for paint (now proven by controlled A/B) · pre-exec zsh chain ~250 ms (237 today) · binary `--version`
floor ~70 ms (55–79) · statusline ~45 ms/render, non-blocking (48.6) · the 7–12 s was fleet-wide, not
reso · `DISABLE_AUTOUPDATER=1` honoured for the binary's internal updater · R6's `setup-task-symlinks`
21 s → 237 ms, `activation-watch` 660–900 → 126 ms, `setup-plan-symlinks` 560 → 69 ms, `session-start`
SWR 2.52 s → 0.036 s **warm** · reso `cmd_claim` genuinely no longer runs `fetch_guarded` or an inline
`pnpm install`.

**Gone stale** — `R4:92 mailbox-drain 0.02 s` (guard measured, not the hook — **the consequential
one**) · R6 "group max ~240 ms / everything sub-second" (refuted for the layer: ~3.97 s on a reused
pane) · R4 "setup-task-symlinks 21 s killed at timeout 5" (fixed, content-verified) · R4
"session-start 2.52 s blocking" (69–88 ms warm) · R4 "settings + permission load ~300 ms" (that
window was a whole phase; rule application is 8 ms, settings parse 0.59 ms) · R4 "skills/commands
159 ms, 93 skills" (32 ms, 91) · R4 "MCP configs resolved 207 ms" (75–86) · R4 "MCP costs ~1.6 s"
(that ablation sat inside its own noise; controlled A/B says ≈0 for paint, ~+0.5 s for dispatch) ·
R4 "input box painted 1.36 s" (1.52 s) · R3 "`cc-close-attrib` ~110 ms" (70–72 with identical flags
on both sides) · R3 "shell startup 310 ms" (240–305) · R6 "claim 200 ms, end-to-end 940 ms"
(conditional on a free slot) · R5-startup-print's `systemMessage` **inside** `hookSpecificOutput`
(only the top-level key renders) · `cc-startup-modals`' "`tui:"default"` keeps panes out of the
alternate screen" (both values emit `ESC[?1049h` on 2.1.220) · zprof's 360 ms compinit (a
double-source artifact; real interactive startup 190–215 ms) · the rc's own header comment above
`claude()` still says `~/.claude-219` while `:496` pins `~/.claude-220`.

---

## 8. Honest unknowns, and the exact probe for each

- **U1 — The cause of the 265–576 ms un-logged stall before each `.claude.json` write (600 ms total,
  the largest remaining block).** Reproducible 6/6, size-independent, contention-independent. A fixed
  ~250–300 ms debounce/flush timer fits the lower cluster but is **unproven — do not report it as the
  cause.** *Probe:* `sudo fs_usage -w -f filesys -t 30 <pid>` on a probe launch, plus
  `CLAUDE_CODE_SLOW_OPERATION_THRESHOLD_MS=50`. Second question, uninstrumented: do all 3–4 writes
  pay it, or only the first?
- **U2 — Is `panda ENOENT` slot-local or repo-wide? HIGHEST VALUE.** If repo-wide, the cold pool
  fallback does not take 20–30 s, it **fails**, and `claude` refuses to launch from the reso primary.
  *Probe:* `pnpm install --frozen-lockfile` in a scratch `git worktree` off `origin/main` **outside**
  the pool, timed, exit code recorded.
- **U3 — Is the harness's hook timeout kill SIGTERM or SIGKILL, and can `mailbox-drain` leave a
  partially-advanced `.seen` cursor when reaped mid-`mailbox_take_n`?** This decides whether M5 is a
  latency bug or a **data-loss** bug. *Probe:* run the hook under a 5 s `timeout` against a seeded
  3-message **copy** of the box; diff `.seen` and the box afterwards.
- **U4 — T_turn to a real first API token has never been measured today.** Every figure here uses
  `/help` as the input-pipeline proxy. *Probe:* one `claude -p 'reply OK'` per arm against a local
  recorder (`ANTHROPIC_BASE_URL=http://127.0.0.1:<port>`) — **zero quota**, technique already proven
  by the upstream axis.
- **U5 — Live mailbox flock contention with ~24 sessions.** All 15–22 s figures were taken against a
  **copy**, deliberately, to exclude it. The live number is ≥ those by an unmeasured margin.
- **U6 — Are pre-composer keystrokes queued or discarded at the source?** Established behaviourally
  (3/3 never echoed within 11 s) but the mechanism is unread inside a 195 MB binary. Operational
  consequence today: **any script that spawns a pane and types must wait for the composer marker,
  never for process start** — `handoff-fire`, `cc-pane-runner`.
- **U7 — Does `~/.claude/rules/*.md` load on 2.1.220?** The config-discovery axis observed it loading
  by two independent channels (the binary's own `Loaded 12 CLAUDE.md/rules files` enumerates
  `agent-operating-lessons.md` at 1 677 chars; and this session's system-reminder carries its text),
  contradicting a memory that measured it dead **twice**. **No design here depends on it.** *Probe:*
  re-run the sentinel the memory itself specifies, from a non-reso cwd, on both binaries; keep the
  token so the claim stays falsifiable, and record the binary version with any verdict.
- **U8 — Cold-cache (post-reboot) figures for everything.** Every number is warm-page-cache; the
  first run of each n≥3 set is consistently ~2× the rest (e.g. total file IO 12.17 → 6.23/6.25 ms),
  so a genuinely cold boot is worse by an unmeasured factor.
- **U9 — Per-config-dir and per-project variation.** Hook measurements used a /tmp project and one or
  two config dirs; reso PROJECT-scope SessionStart hooks were last measured at ~0.02 s warm (R4) and
  not re-derived. `config-mirror-assert` is known to early-exit for `~/.claude` specifically, so at
  least one hook varies by account.
- **U10 — Behaviour under a coordinated 10-session wave.** All figures were taken under ambient load
  14–24 but no wave. The fork-heavy items (`_cc_tlid`, the 20-fork exhausted-pool scan, the alias
  walk) degrade superlinearly there and were not measured in that regime.

---

## R1 — Recovery addendum (2026-08-16, post-transplant): the SWR ruling is overturned, and the fix is one line

This section is APPENDED, not merged into §6 — the original ruling stays visible above with its
reasoning intact, because *how* it was wrong is the transferable part.

The verifier slot for this claim died three times (session limit, then `ECONNRESET` ×2 during an
operator connectivity drop) and was the only genuinely unfinished unit in the wave. It was re-run
from its salvaged prompt. Its verdict inverts §6 row 2.

**What §6 got right:** there is no "drift". The claimed 45% growth in deferred MCP work is an
instrument artifact — `sessions.log` pairs start/answer for n=313 real probes since the fix and the
median is 3.0 s on *every* day 08-11 → 08-15; a same-composition split is 3.23 → 3.07 (*down*).
Duration tracks server count, not date. The keep-warm cadence change (60→180 s) is likewise a
non-issue: the launcher reads `--max-age 600`, so a 180 s cache is always a hit.

**What §6 got wrong, and it is the load-bearing half.** "A process nothing blocks on" measured the
wrong terminus. The harness reads a hook's stdout **to EOF**, and EOF does not arrive while any
descendant still holds fd 1. `_mcp_spawn_refresh` redirected the inner `bash` but not the enclosing
`( … ) &`, so the subshell inherited the harness pipe:

| clock, same hook, n=5 | result |
| --- | --- |
| process exit (what §6 measured) | **83 ms** |
| pipe EOF (what the harness waits on) | **3 096 ms** |

pty A/B, n=3/arm, isolating the mechanism: `( sleep 6 ) &` → `/help` at 6.42/6.44/6.55 s;
`( sleep 6 ) >/dev/null 2>&1 &` → 1.39/1.40/1.40 s. End-to-end on the real hook, stale cache
3.514/3.594/3.701 s vs fresh 1.373/1.389/1.403 s = **+2.2 s**. The configured `timeout: 10` does
**not** cap it, because the hook process itself has already exited (12 s fixture → 12.48 s blocked).

**Corrected classification: BLOCKING** (input pipeline — same class as `mailbox-drain`), **+2.2 s
p50 / +4.2 s p90, unbounded tail, on the 54.4% of starts that run a probe.** The wave's unexplained
"31.6 s cold tail" is now readable: 31.6 s of *blocked input*, aggravated on hosts where
`timeout`/`gtimeout` is unresolvable (PATH lacking `/opt/homebrew/bin` — reproduced independently
in this session), which makes the hook's own `PROBE_TIMEOUT` inert.

**Why this changes scheduling, not just the ledger.** On reused panes this stall was *masked* by
`mailbox-drain`'s 5 s reap. Fix `mailbox-drain` alone and this becomes the new group max —
**halving S1's promised ~4 s win on ~54% of starts.** The two fixes are therefore a single unit of
work, and shipping S1 without this one would have produced a real improvement that looked like a
disappointing one, with no obvious culprit.

### Landed (this session, commit `55e7ffb0d`)

| # | Change | Measured |
| --- | --- | --- |
| R1 | `session-start.sh:187` — redirect the **subshell**, not just the inner `bash` | minimal repro 4.05 s → **0.04 s** to pipe-EOF (n=3/arm) |
| S1 | `mailbox-pending.sh:548` — memoised one-pass tip set | **5.54–5.89 s → 0.04–0.05 s** (~120×), n=5; set-equivalence vs the old scan on the live store: 1,296 tips both ways, **0 missing, 0 extra** |
| D2 | `mailbox-drain.sh:244` — bounded adoption take (`CC_MBX_ADOPT_MAX_LINES`, default 200) | prevents a 2.26 MB / ~566K-token box entering turn-1 context once S1 makes adoption complete |

Green: `mailbox-{session-key,drain,cover-pane,forward,midturn}.bats`, 97 tests, exit 0.
**Not landed:** S2–S5 (shell trim, ~135 ms) and the `.alias` prune (red-team D5 — destructive,
needs the never-delete-a-live-tip rule and a dry-run first). Both remain open work.

### The generalisable lesson, which outranks the milliseconds

Three separate measurements of this hook were correct and useless, each because the instrument
excluded the thing being measured:

1. R4/R6 benchmarked `mailbox-drain` under `env -u ITERM_SESSION_ID` — its exact early-exit guard.
   **0.02 s recorded for a 15–22 s hook.**
2. §6 above timed the SWR refresher to *process exit* when the harness waits on *pipe EOF*.
   **83 ms recorded for a 3,096 ms stall.**
3. The 15–22 s figures were taken against a *copy* of the mailbox to exclude flock contention, so
   the post-fix residual still carries an acknowledged error term in the unsafe direction.

In every case the number was reproducible and the *terminus* was wrong. A latency measurement is
only as good as its definition of "done", and on this box "done" has repeatedly meant something
different to the harness than to the process. Prefer end-to-end, harness-visible acceptance
(`T_help` on a **reused** pane) over any component timing — which is why the red-team replaced the
absolute gate with the instrument-independent delta `T_help_render − T_help_typed ≤ 250 ms`.

---

## R2 — Follow-on sweep (2026-08-17): S3 and S5 are DROPPED, not deferred; S2's premise was wrong

The operator asked for every remaining free win and loose end completed. Working them produced
three reversals, so this section records the *reasons*, which outlive the items.

### DROPPED — S5 (`_cc_sync_account` generation stamp, claimed 54 ms)

**It re-arms a measured two-day fleet-wide auth outage.** The proposed key is "`~/.claude`'s mtime
+ entry count unchanged", and the skip would bypass not just the share loop but the **heal** and
**reap** branches below it. The reap loop exists for a transient lock captured then released — and
in exactly that scenario the entry count returns to its previous value, so the stamp reads
*unchanged* precisely when the reap is needed. That is the incident `config-mirror.zsh:92-105`
documents in its own comment: dangling `.oauth_refresh.lock` symlinks "disabled the in-session
OAuth token refresh on all four accounts", producing "an 8-hourly logout-while-working for two
days". 54 ms does not buy that risk. The doc's original risk line ("degrades silently") understated
it — reading the code shows the skip removes the *only* mechanism that repairs the condition.

### DROPPED — S3 (route verdict → T4 flat file, claimed 75 ms)

Two independent reasons, both measured today:

1. **The recoverable time is ~20 ms, not 75.** Decomposed: bare `python3 -c pass` = 20 ms; compiling
   the 4,424-line script = **45–50 ms** (n=5) — pure waste, since a directly-run script is `__main__`
   and Python never caches its bytecode; the actual work ≈ 30 ms. Total measured 90–110 ms today. A
   stub+module prototype (so the bytecode caches in `__pycache__`) produced byte-identical `--route`
   output and rc, and moved 0.09 s → 0.07 s. **20 ms, ~1% of the floor.**
2. **Both implementations break a contract.** The doc's version (precompute the verdict at
   keep-warm time) silently stops `log_route_decision()` from running — the record that
   `claude-accounts:4283` calls out as load-bearing ("the desk decision goes on disk BEFORE either
   exit path, so an abstention is recorded as faithfully as a pick"), or else duplicates the jsonl
   schema in zsh, where it will drift. The stub version must relocate the `if __name__` wrapper
   whose exit-5 semantics `handoff-fire` reads to decide **"a wave is safe to fire"**.

Re-open only if `claude-accounts` is restructured for another reason; then the stub is free.

### CORRECTED — S2's "nothing is printed" is false

`worktree-pool.sh:79` is `log() { echo "→ worktree-pool: $1" >&2; }`, and the launcher captures the
claim via `$( … )`, which takes **stdout only** — so the cold-path line has always reached the
operator's terminal. The fallback was never silent. What it omitted was the *cost*. Landed the
one-line fix instead of the proposed refuse-and-print: name the 20–30 s and the pre-warm command,
then proceed. A refusal converts a slow success into a hard error, and the pool self-heals
(observed 0/10 → 3/10 unaided in 3 h), so exhaustion is transient. Applied to **both** the repo copy
and `~/.reso/bin/worktree-pool.sh`, which is a standalone copy, not a symlink — editing only the
repo would have been an inert change (landed ≠ live).

### LANDED

| Item | Result |
| --- | --- |
| S4 — daily-stamp `cc-close-attrib`'s two sweeps | **20 ms** off every launch (measured, n=6; doc said 30) |
| S7 — remove `mac-messages` | 4 config dirs (not the 3 predicted). 650 MB / 18 procs for **0 invocations across 7,196 transcripts, all time**. Capability preserved: the `msg` CLI covers it (213,985 messages, verified). Registration backed up to `mac-messages-registration-backup.json` |
| S9 — six reso rules files | ~20K tokens/session recovered; frontmatter to line 1, directive below; markdownlint 0 issues |
| `.alias` GC | `bin/cc-mailbox-alias-gc`, dry-run default, theft-free by construction. **Deletes nothing today** — oldest file is 19 d, all 1,243 tips have live transcripts |
| reso `land-status.sh` | The money gate reported "no creds / API down" when `aws` was merely off-PATH. Three UNKNOWNs → three green reads |

### FILED, not done — S8 (`ms365` → opt-in)

Fails the Follow-On Gate's F1: 188 tool definitions / 1.3 GB, but **0.24% use is not 0%**, and the
doc itself calls it "a judgement, not a measurement". Removing a capability the operator uses
occasionally is a downside a reasonable operator would weigh, so this is theirs to call, not an
auto-land. Re-add after removal is
`claude mcp add ms365 -s user -- <cmd>`; the current registration is in every
`~/.claude*/.claude.json` under `mcpServers.ms365`.

### The pattern, now at four instances

Every item in this sweep failed or succeeded on the same axis as the original bug — **the
instrument, not the code**. S2's premise was an unread stderr stream. `land-status.sh` blamed
credentials for a PATH. The `.alias` guard's first oracle was circular and its second under-reported.
And the original `mailbox-drain` finding existed only because two prior waves had benchmarked an
early-exit guard. Before trusting any measurement here, ask what the instrument had to exclude in
order to produce it.
