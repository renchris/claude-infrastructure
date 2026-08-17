# Regression archaeology — the startup speed-up, the post-startup unresponsiveness, and what is live today

Agent: regression-archaeology axis. Started 2026-08-16. Raw notes, appended as I go.

## Prior art read (claims, not yet re-verified)

### R3-shell-latency.md (measured 2026-08-11, R6 addendum 2026-08-12)
Pre-exec zsh chain. Claims:
- chain ~250ms from ordinary cwd, ~1.9-2.2s from reso PRIMARY checkout
- two unbounded arms: untimed `git fetch origin main` (12,064ms with stalled transport),
  and `pnpm install --frozen-lockfile` first-touch per pool slot (11,022-14,034ms)
- **R6 fix landed 2026-08-12**: reso `1211088d7` (pool + db-ensure), infra `a09ce88e3` (launcher).
  - `cmd_claim` provisions NOTHING — no fetch_guarded, no refresh_slot, no unconditional db-ensure
  - "a stale slot is SERVED at its base; ensure refreshes **behind the claim** (gc.wake)"  <-- CANDIDATE TRADE
  - end-to-end control 2,713 -> 940 ms

### R4-cc-latency.md (measured 2026-08-11, R6 addendum 2026-08-12)
Post-exec. Claims:
- `setup-task-symlinks.sh` ran 21-22s, killed by its own timeout:5 => 5s blocking floor, work discarded
- `session-start.sh` shells out to a second whole `claude` CLI for `mcp list` = 2.52s
- SessionStart hooks BLOCK (sleep 25 => +22.5s)
- group cost = MAX of concurrent hooks
- **R6 fix landed 2026-08-12** (infra `a09ce88e3`), plus earlier desk-router session:
  - `find_active_list` single-pass `d31fee77f` (21s -> 0.09s)
  - session-start mcp **SWR** `1d03837c` (2.03s -> 0.036s)   <-- CANDIDATE TRADE (stale-while-revalidate = background refresh)
  - activation-watch 660-900ms -> 126ms
  - setup-task-symlinks 800ms -> **237ms blocking**, with "index prune + 2,479-dir summary sweep +
    NEW empty-dir GC moved to a **detached, stamp-throttled `--sweep` self-reentry**" <-- CANDIDATE TRADE
  - setup-plan-symlinks 560ms -> 69ms
  - group max ~900ms -> ~240ms

### R5-startup-print.md
Not a latency doc — SessionStart hook OUTPUT CHANNEL analysis (systemMessage vs additionalContext).
Recommends adding a `session-start-accounts.sh` hook with 0.5s timeout + 90s cache. Accretion candidate.

### RESTART-BRIEF-2026-07-27.md
NOT about startup latency. It is about the landing gate / postland 0-green deadlock and machine LOAD
(load ceiling 8; observed 88-104). Relevant only as evidence that machine load is a confounder.

### cc-startup-modals-2026-08-04.md
Modal suppression (`tui:"default"`). Not latency. Relevant: spawned sessions wedging at modals.

### mcp-modal-fire-stall-2026-08-15.md
`.mcp.json` approval modal blocks fired panes. Not latency.

## Hypothesis going into git
The R6 (2026-08-12) speed-up used THREE deferral mechanisms, each of which converts blocking startup
cost into concurrent post-startup work:
  T1. worktree-pool: serve a stale slot, refresh **behind the claim** (pnpm install now runs while
      you work, 11-14s of local CPU)
  T2. setup-task-symlinks: detached `--sweep` self-reentry over ~2,400 dirs
  T3. session-start.sh: MCP status stale-while-revalidate => background `claude mcp list`
      (a SECOND 257MB CLI) spawned post-startup
That is the "traded startup speed for post-startup responsiveness" the operator remembers.
TO VERIFY BY CONTENT.


---

## TIMELINE ESTABLISHED (git + transcripts, content-verified)

| Date (local) | Event | Evidence |
|---|---|---|
| 2026-04-17 | `665f53d7c fix(claude-latest): default-deny unknown versions in MANIFEST gate` — the stable wrapper stops auto-installing anything not in MANIFEST. Side effect nobody noticed: `installed` is now permanently < npm `latest`. | git |
| 2026-08-10 00:51 | `37a87cd4f` last touch of `bin/claude-latest` (goal birth-watcher). Wrapper frozen since. | `git log origin/main -- bin/claude-latest` |
| 2026-08-10 | plan `docs/plans/START_LATENCY_ROUTER.md` opened — `claude1` pin + bare `claude` auto-routes; keep-warm daemon designed so the routing read is never a cold sweep. "at a start cost that cannot regress". | plan |
| 2026-08-10 22:56 | `9a843f988` the `score_interactive` desk lane lands (agent-authored). | plan §2.2 |
| 2026-08-10 23:21 | `23bbf259d feat(accounts): --keepwarm producer` + staged plist, **StartInterval 60 / --max-age 30**. | git |
| **2026-08-11 08:32Z** | **OPERATOR ACTIVATES the router** — `36-start-latency-router-activate.sh` appends the source line to `~/.zshrc`, flips `accounts[0].launcher claude→claude1`, "keep-warm LOADED (StartInterval 60, refresh-ahead --max-age 30)". | transcript `<bash-stdout>` 2026-08-11T08:32:46Z |
| **2026-08-11 20:10Z (13:10 PDT)** | **THE COMPLAINT.** Operator: *"We just used 'claude' here for the first time but it looks like a) **Claude Code is not responsive for the first 7-12 seconds or so** and b) it looks like it routed us to Account3…"* | transcript `-worktrees-wt-pool-1` 2026-08-11T20:10:38Z |
| 2026-08-11 14:22 PDT | R1–R8 research lands (`80918edad`): the 7-12 s is **NOT the router** — it is `setup-task-symlinks.sh`, fleet-wide, pre-existing. | commit body |
| 2026-08-11 14:42 PDT | `d31fee77f`/`8d642bca` — `find_active_list` single-pass. Hook **28.699 s → 0.598 s**. | plan §W0 outcome |
| 2026-08-11 14:51 PDT | `1d03837c`/`d0f5966b4` — session-start MCP probe **stale-while-revalidate**, 2.030 s → 0.036 s warm. | plan §W0 outcome |
| 2026-08-11 18:44 PDT | `0ffe96995` — keep-warm **StartInterval 60 → 180, --max-age 30 → 90**. Reason: the warmer polled tighter than the OAuth throttle window and was excluding 3 of 4 accounts from routing. | commit body |
| **2026-08-12 01:35Z (Aug 11 18:35 PDT)** | Operator, still: *"when I entered 'claude', it **hangs on routing for a good dozen seconds**, and it routed to Account 4"*. | transcript `-worktrees-wt-pool-2` |
| 2026-08-12 03:27Z | Operator boots the new (180 s) keep-warm plist. | transcript `<bash-input>` |
| 2026-08-12 04:04 PDT | `a09ce88e3` — `_cc_route_check` was running a **five-week-stale** pool script from the primary checkout; repointed at the self-updating trunk copy. This is what made every pool fix REACHABLE. | commit + R3 §R6 |
| 2026-08-12 | `22e2c4317` — SessionStart group max **~900 ms → ~240 ms** (activation-watch 660-900→126, setup-task-symlinks 800→237 blocking + detached `--sweep`, setup-plan-symlinks 560→69). | R4 §R6 |
| 2026-08-12 | reso `1211088d7` — `cmd_claim` provisions NOTHING; fetch+reset+pnpm+db-ensure leave the claim path. End-to-end 2,713 → 940 ms. | R3 §R6 |
| 2026-08-12 → 2026-08-16 | **NOTHING touches any of these files on trunk.** | `git log origin/main --since=2026-08-11 -- <all hook + launcher files>` |

## Q3 — REVERTED / PARTIAL / STILL IN PLACE? → **STILL IN PLACE. Verified by content, not by commit.**

| Fix | Live file | Verified |
|---|---|---|
| `find_active_list` single-pass | `~/.claude/hooks/lib/task-helpers.sh` (symlink → repo) | ONE `jq` read of the index + pure-bash `-nt` scan; the per-dir `jq --arg k` fork is gone from this fn. Content-identical to `origin/main`. |
| session-start MCP SWR | `~/.claude/hooks/session-start.sh` | `MCP_CACHE_TTL=300`, `MCP_CACHE_MAX_AGE=86400`, "serve it AND detach a background refresh". Identical to trunk. |
| setup-task-symlinks detached sweep | `~/.claude/hooks/setup-task-symlinks.sh` | `store_sweep()` + `--sweep` self-reentry, `( "$0" --sweep </dev/null >/dev/null 2>&1 & )`, stamp-throttled `CC_TASKS_SWEEP_MIN_S=600`. Identical to trunk. |
| activation-watch batched | `~/.claude/hooks/activation-watch.sh` | ONE `LC_ALL=C diff -rq`, ONE `grep -HoE`. Identical. |
| setup-plan-symlinks single awk | `~/.claude/hooks/setup-plan-symlinks.sh` | single awk pass. Identical. |
| reso pool claim-serves | `~/.reso/bin/worktree-pool.sh` (mtime Aug 12 04:20) | `cmd_claim` has no `fetch_guarded`/`refresh_slot`/unconditional db-ensure; the comment naming the removal is in place. |
| launcher prefers trunk pool script | `~/.claude/lib/claude-launcher.zsh` → repo symlink | live |

**No revert commit exists.** `git log origin/main --since=2026-08-11` over every one of these paths returns
only the R6 commits themselves. So the operator's hypothesis "we may have regressed back to a slower
start-up time" is **FALSE as a code fact** — nothing was traded back.

## 🚨 CORRECTION TO THE LEAD'S GROUND TRUTH — `~/bin/claude-latest` IS NOT ON THE `claude` PATH

The brief states "`_claude_pinned` ultimately runs `~/bin/claude-latest`". **Measured false.**

`~/.zshrc:451` `claude()` body, line `:498`:
```
local _bin="$HOME/.claude-220/node_modules/.bin/claude"
... "$HOME/.claude/bin/cc-close-attrib" "$_bin" --permission-mode ... --model ... --effort ...
```
Live probe (`zsh -lic`): `typeset -f _claude_pinned | grep -c claude-220` → **1**;
`| grep -c claude-latest` → **0**. `claude-latest` appears in `~/.zshrc` only at `:173`/`:175`,
inside **`claude-prev`** — the retired stable 2.1.114 track.

So the lead's measured 1.28–1.50 s for `~/bin/claude-latest --version` is a real number about a
wrapper the operator's `claude` never executes. Measured split, /tmp, n=5:

```
~/.claude-versions/current/node_modules/.bin/claude --version   0.43 0.05 0.06 0.05 0.05   -> median 0.05 s
CLAUDE_SKIP_UPDATE=1 ~/bin/claude-latest --version              0.19 0.20 0.19 0.19 0.27   -> median 0.19 s
```
i.e. the wrapper's non-network overhead is ~0.14 s. The remaining ~1.1 s the lead saw is
`update_if_needed`'s `npm view` — see the latent defect below.

## LATENT DEFECT FOUND (real, but on `claude-prev`, not `claude`): the update cache can never hit

`bin/claude-latest:155-177`. Cache hit requires `cache_age < 600 && cached_version == installed`.
`cached_version` is what was written from `available=$(timeout 3 npm view …)`.

- installed = `2.1.114` (`readlink ~/.claude-versions/current`)
- npm latest = **`2.1.233`** (measured now)
- MANIFEST default-deny (`665f53d7c`, 2026-04-17) means installed will NEVER advance to `available`.

⇒ `cached_version(2.1.233) == installed(2.1.114)` is **permanently false** ⇒ the 10-minute cache
never hits ⇒ **`timeout 3 npm view` runs on every `claude-prev` launch**.
Measured `npm view @anthropic-ai/claude-code version`, n=6, ms: `390 454 1131 467 426 866`
→ median **~460 ms**, max 1131 ms, hard-bounded at 3000 ms.
(The cache file currently *does* hold `2.1.114` — because one `npm view` failed and the
`|| echo "$installed"` fallback wrote the installed version. That is an accidental 10-minute
cache hit, not the designed one.)

**Why the prior art missed it:** R4 §6 asked *"Is `DISABLE_AUTOUPDATER=1` honoured?"* and answered
*"Yes. No update check in the debug log."* That is true of the **binary's internal** autoupdater
(`claude-latest:341` exports it) and says nothing about the **wrapper's own npm check** one layer up.
R3's stage table (`§2`, stages 0–7) has **no `claude-latest` row at all** — its chain stops at `exec`
and R4's starts after it. `~/bin/claude-latest` sits in the seam and was never timed by either.

---

## THE CRUX — the mechanism that traded startup speed for post-startup work

The R6 speed-up (2026-08-11/12) bought every one of its wins with the SAME move:
**deferral by detachment** — take O(store) / network / install work off the blocking launch path
and re-issue it as a DETACHED CHILD that runs concurrently with the operator's first turn.
Three instances, all still live:

### T1 — `hooks/session-start.sh`: stale-while-revalidate (`1d03837c` / `d0f5966b4`)
Blocking `claude mcp list` 2.03 s → 0.036 s warm. The mechanism, in the hook's own words:
*"stale cache (<= MAX_AGE) -> serve it AND **detach a background refresh** for the NEXT start."*
The detached child is **a second full 257 MB Claude CLI** booting and connecting **6 MCP servers**.

Measured TODAY (`env -u CC_PANE_ID -u ITERM_SESSION_ID CLAUDE_CONFIG_DIR=~/.claude-tertiary
~/.claude-220/node_modules/.bin/claude mcp list`, n=3):
```
3974 ms   3732 ms   4584 ms      -> median 3,974 ms
```
Prior art (`hooks/session-start.sh:87`, 2026-08-11): `2.89 / 2.51 / 2.58 s`.
**→ the deferred work has grown ~45% since the fix landed** (MCP server accretion; `mac-messages`
was added 2026-08-15 per `mcp-modal-fire-stall-2026-08-15.md` M4).

Fires whenever that config dir's cache is older than `MCP_CACHE_TTL=300`. Live right now:
```
.claude          : ABSENT      (=> inline probe on first start)
.claude-secondary: age 76 s    fresh
.claude-tertiary : age 442 s   STALE -> detaches
.claude-next     : age 44,408 s STALE -> detaches
.claude-quaternary: age 2,873 s STALE -> detaches
```
🚨 **And the SWR has a CLIFF.** Past `MCP_CACHE_MAX_AGE=86400` the hook refuses to serve and probes
**INLINE — blocking — again**. `.claude-next` is the DEFAULT config dir for bare `claude`
(`~/.zshrc:460  _cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"`) and it sits at **44,408 / 86,400 s
= 51% of the way to that cliff**, i.e. its detached refresh is NOT landing. When it crosses, bare
`claude` re-acquires a ~4 s blocking probe inside a `timeout 10` hook.

### T2 — `hooks/setup-task-symlinks.sh --sweep` (`22e2c4317`)
Index prune + store-wide `_summary.json` sweep + a NEW empty-dir GC over the whole task store moved
to `( "$0" --sweep </dev/null >/dev/null 2>&1 & )`, stamp-throttled to `CC_TASKS_SWEEP_MIN_S=600`.
Store is **2,578 dirs** today (2,428–2,479 on 2026-08-11, +4–6%). The stamp is FLEET-SHARED — all
five config dirs' `tasks/` resolve to one store (all five `.sweep-stamp` read age 445 s, identical)
— so at most one sweep per 10 min box-wide. Bounded; the smallest of the three.

### T3 — reso `scripts/worktree-pool.sh` `cmd_claim` (reso `1211088d7`)
`cmd_claim` provisions NOTHING. Its own comment: *"This used to run fetch_guarded … and then
refresh_slot inline — a `git reset` plus `pnpm install --frozen-lockfile` (11-14s first touch on a
stale slot) plus an unconditional db-ensure (~0.3s) — all on the interactive `claude` launch path."*
A stale slot is now **SERVED at its base** and refreshed **behind the claim** (`worktree-gc.wake`).
The 11–14 s `pnpm install` did not vanish; it moved to a background ensure that runs while the
operator's first turn is in flight. Live copy `~/.reso/bin/worktree-pool.sh` (Aug 12 04:20) verified.

**So the trade is real, deliberate, documented, and STILL IN PLACE.** ~5 s came off the blocking
path; the box acquired ~4 s of second-CLI boot per stale-cache start + a periodic 2,578-dir sweep +
(in reso) an 11–14 s pnpm install, all timed to fire exactly when the operator starts working.

## 🚨 BUT THE OPERATOR'S CAUSAL STORY IS INVERTED — dates settle it

- Unresponsiveness reported: **2026-08-11T20:10:38Z** (13:10 PDT).
- The deferrals landed: **14:42 / 14:51 PDT (21:42 / 21:51Z) on 2026-08-11** and **2026-08-12**.

The deferral cannot have caused the complaint that motivated it. What the operator hit on
2026-08-11 was the **pre-existing, fleet-wide** floor R4 measured: `setup-task-symlinks.sh` running
21–22 s, killed by its own `timeout: 5`, work discarded, on **every** start in **every** project in
**every** config dir — plus `session-start.sh`'s 2.52 s `claude mcp list`. R4 proved it was not the
router by reproducing the identical settle points (5.75 s / 9.05 s) in an **empty /tmp project**.

The router (activated 08:32Z the same morning) was simply the first thing the operator had touched.
Post hoc ergo propter hoc — and the measurement wave was commissioned *because* of that suspicion
and refuted it the same day.

## Q4 — is today's slow start the revert, drift, or something new?

**Not the revert (there is none), and not drift in the shell chain.** Every R3/R4 headline stage
re-measured today, /tmp, n≥3:

| Stage | prior art | today (ms) | median | verdict |
|---|---|---|---|---|
| `zsh -lic true` | 310 ms (R3 §2 stage 0) | 428 · 305 · 246 | **305** | HOLDS |
| `claude-accounts --route interactive --max-wait 0 --max-age 600` | 75 ms (R3 §2 1a) | 136 · 85 · 86 · 80 · 84 | **85** | HOLDS |
| 2.1.220 binary `--version` | 70 ms (R4 §1 stage 1) | 79 · 83 · 73 · 77 · 81 | **79** | HOLDS |
| `statusline.sh` per render | 45 ms (R4 §1 stage 13) | 63 · 54 · 49 · 49 · 67 | **54** | HOLDS (+20%, noise) |
| `claude mcp list` (the DEFERRED work) | 2,510–2,890 ms | 3974 · 3732 · 4584 | **3,974** | **STALE — grew 45%** |

Startup-path composition since 2026-08-12: **unchanged**. Same 15 SessionStart hooks, byte-identical
list across all five config dirs, `accounts-board.sh` still NOT wired (migration `0011` staged, not
activated). `git log origin/main --since=2026-08-12 -- hooks/` shows no new SessionStart entry.

What HAS changed is (a) the deferred MCP work grew 45%, (b) the task store grew 4–6%, and (c) the
box is loaded: `uptime` = **load 14.95 / 15.79 / 18.04**, 9 live `claude.exe`, `XprotectService` at
75% CPU, `postland-verify.sh` running 38 min. The land-gate's own ceiling is load 8
(`RESTART-BRIEF-2026-07-27.md` §1).

## Prior-art verdict — what still holds, what is stale

| Claim | Source | Verdict today |
|---|---|---|
| `setup-task-symlinks.sh` = 21–22 s / 5 s cap | R4 §VERDICT | **STALE — FIXED.** Single-pass `find_active_list` verified in the live file. |
| `session-start.sh` `claude mcp list` = 2.52 s blocking | R4 §5 | **STALE — DEFERRED,** not removed. Now 3.97 s detached. |
| SessionStart hooks BLOCK (`sleep 25` → +22.5 s) | R4 §3 | **HOLDS** (structural). |
| group cost = MAX of concurrent hooks | R4 §2a | **HOLDS** (structural). |
| pre-exec chain ~250 ms off the reso primary | R3 §3 | **HOLDS** — route 85 ms, shell 305 ms re-measured. |
| `git fetch` unbounded on the claim path (12,064 ms) | R3 §4 | **STALE — FIXED** (`cmd_claim` no longer fetches; `fetch_guarded` is `timeout 30`). |
| `pnpm install` 11–14 s on the claim path | R3 §4 | **STALE — MOVED,** not removed (T3 above). |
| "DISABLE_AUTOUPDATER honoured, no update check on the path" | R4 §6 | **TRUE of the binary, MISLEADING as an answer** — it does not cover `~/bin/claude-latest`'s own `npm view`. |
| `tui:"default"` keeps panes out of alt-screen | cc-startup-modals §0 | **REFUTED** by the plan's own §2.5 (both values emit `ESC[?1049h` on 2.1.220). |
| "93 skills", "492 allow rules" | R4 §1/§5 | **NOT COMPARABLE** — those were binary-merged / project-local counts; `~/.claude/skills` = 35, user `settings.json` allow = 339. Do not read as a change. |
| R5's `hookSpecificOutput.systemMessage` recommendation | R5 | **REFUTED** by the lead probe in `DESK_ROUTER_AND_STARTUP_V1.md §2.7` — that form is silently ignored; the TOP-LEVEL key is the one that renders. |
| RESTART-BRIEF-2026-07-27 | — | **NOT startup prior art at all** — it is the landing-gate / postland deadlock. Only relevant as the source of the load-8 ceiling. |

## UNKNOWN / not measured here
- Time-to-first-paint and time-to-interactive under a pty TODAY (R4's 1.36 s / 5.85 s / 9.26 s).
  Not re-run: a real session start arms `mailbox-wake-arm` (4 h watcher), writes `session-register`
  and `dod-persist`, and a throwaway `CLAUDE_CONFIG_DIR` would carry none of the hooks under test.
- The SessionStart GROUP cost today (R6 claims ~240 ms). Owned by the sibling hook-timing agent.
- Whether the `.claude-next` detached MCP refresh is failing or simply never dispatched (its cache
  is 12.3 h old). Needs a look at `~/.claude-next/.claude/logs` — not done.
- Cost of `store_sweep` when it fires (2,578 dirs). Not run: it mutates the live task store.
