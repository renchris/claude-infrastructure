# R3 — Pre-exec shell-chain latency for bare `claude`

Measured 2026-08-11 on this machine, all numbers with the command that produced them.
Read-only: no tracked file edited. Three pool slots were claimed as probes and **restored**
(`git switch pool/slot-N` + branch deleted; `worktree-pool.sh status` verified back to 7 READY).

---

## 1. Verdict first

**The pre-exec shell chain costs ~0.25 s from an ordinary cwd and ~1.9–2.2 s from the reso
PRIMARY checkout. On a healthy machine it does NOT explain 7–12 s — it explains ~20–25 % of it.
The remainder is post-exec (sibling agent's half).**

But the chain has **two unbounded arms** that land squarely in the 7–12 s band, and both fire
only from the reso primary checkout:

| Pathological arm | Measured | Trigger |
|---|---|---|
| `git fetch origin main` with a stalled transport (**no timeout wrapper anywhere**) | **12,064 ms** | any degraded/flapping network, VPN, DNS, GitHub SSH slow |
| pool slot behind `origin/main` ⇒ `pnpm install --frozen-lockfile` **first touch** | **11,022 – 14,034 ms** | operator lands a commit, then launches before the background `ensure` refreshes the slot |

Either one alone produces exactly the reported symptom. Both are silent — nothing prints while
they run.

---

## 2. Per-stage table

Bench harness: `/tmp/r3-bench.zsh` (zsh/datetime `EPOCHREALTIME`), run inside `zsh -lic`, n≥5
unless noted. "Critical path" = blocks the exec of the claude binary.

| # | Stage | median ms | spread (n) | crit? | file:line |
|---|---|---|---|---|---|
| 0 | shell startup `zsh -lic true` | **310** | 285–342 (6) | new pane only | `~/.zshrc` |
| 0a | ├ `compinit` (zprof, instrumented) | 456 | (1) | — | oh-my-zsh |
| 0b | └ `is_update_available` (omz upgrade check) | 119 | (1) | — | `check_for_upgrade.sh:126` |
| 1 | `_cc_route_config_dir` **whole** | **96** | 92–105 (5) | YES | `claude-launcher.zsh:42-85` |
| 1a | ├ `claude-accounts --route interactive --max-wait 0 --max-age 600` (cache HIT) | 75 | 74–77 (7) | YES | `claude-launcher.zsh:59` |
| 1b | ├ same, cache MISS → abstain rc=3 | 71 | 70–72 (5) | YES | `bin/claude-accounts:1861` |
| 1c | ├ same, **single-flight lock HELD by another process** | 73 | 69–113 (4) | YES | proven non-blocking |
| 1d | ├ `_cc_launcher_map` (source generated map) | 0.1 | 0.1–0.2 (5) | YES | `claude-launcher.zsh:33-38` |
| 1e | └ backgrounded `--assign` fork | **2.6** | 2.5–3.7 (5) | **NO** | `claude-launcher.zsh:84` |
| 2 | `_cc_route_check` — non-git / linked worktree (early return) | **8.2** | 8.0–8.6 (5) | YES | `~/.zshrc:106` |
| 3 | `_cc_route_check` — **reso PRIMARY** → pool claim, cold fetch stamp | **1614** | (1) | YES | `worktree-pool.sh:cmd_claim` |
| 3a | ├ `git fetch origin main` | **1382** | 1346–1780 (5) | YES | `fetch_guarded` |
| 3b | ├ claim with fetch stamp <15 s | 353 | (1) | YES | |
| 3c | ├ `git status --porcelain` (slot dirty check) | 57 | (1) | YES | `cmd_claim` |
| 3d | ├ `db-ensure.sh` (runs on EVERY claim) | 266 | (1) | YES | `refresh_slot` |
| 3e | ├ `git reset --hard origin/main` | 73 | (1) | only if stale | `refresh_slot` |
| 3f | ├ **`pnpm install --frozen-lockfile` — first touch** | **12,505 / 14,034 / 11,022** | 3 slots | only if stale | `refresh_slot` |
| 3g | ├ same, warm (2nd+ run same slot) | 320 | 316–335 (3) | | |
| 3h | └ `prepare-cached.sh` | 204 | (1) | only if stale | `refresh_slot` |
| 4 | `_cc_lib _cc_resume_pin cc-resume-shell.sh` | **0.5** | 0.4–0.5 (5) | YES | `~/.zshrc:413` |
| 5 | `_cc_sync_account ~/.claude-next` (same-account dir) | **26.5** | 25.6–35.7 (5) | YES | `config-mirror.zsh:247` |
| 5a | `_cc_sync_account ~/.claude-tertiary` (cross-account) | **47.3** | 47.1–50.3 (5) | YES | |
| 6 | `_cc_tlid` (2 × git rev-parse + basename) | **19.9** | 19.7–21.0 (5) | YES | `~/.zshrc:88` |
| 7 | `cc-close-attrib` wrapper overhead | **~110** | 273–552 wrapped vs 162–633 bare (3) | YES | `~/.claude/bin/cc-close-attrib` |

---

## 3. Totals and the fraction of 7–12 s explained

| Scenario | pre-exec budget | % of 7 s | % of 12 s |
|---|---|---|---|
| cwd = anywhere but the reso primary (incl. every linked worktree) | **~250 ms** | 3.6 % | 2.1 % |
| reso PRIMARY, warm pool, fetch stamp <15 s | **~600 ms** | 8.6 % | 5 % |
| reso PRIMARY, warm pool, fetch cold ← **the common case** | **~1.9 s** | 27 % | 16 % |
| reso PRIMARY, slot behind trunk | **~13–16 s** | >100 % | >100 % |
| reso PRIMARY, degraded network | **unbounded; 12.1 s measured** | >100 % | 100 % |
| pool empty → cold `new-worktree.sh` | 20–30 s (script's own documented figure, `worktree-pool.sh:18-20`) | | |

**End-to-end control**, the single strongest number:
`cd ~/Development/reso-management-app && rm -f ~/.reso/last-fetch && zsh -lic 'claude --version'`
= **2,713 ms** wall clock, of which ~310 ms is shell startup and ~200–350 ms is the binary's own
`--version`. ⇒ **chain ≈ 2.1–2.2 s.** Same command from `/tmp` = **688–1,064 ms** ⇒ chain ≈ 250–430 ms.

**Honest negative result:** on a healthy machine, with a current pool and a working network,
the shell chain is ~2 s at worst and the other 5–10 s of the operator's 7–12 s is post-exec.

---

## 4. Every stage >100 ms — what makes it slow, and can it be moved off the path

### 3a `git fetch origin main` — 1.38 s, **unbounded, no timeout** (the highest-leverage fix)
`fetch_guarded` (`worktree-pool.sh`) guards only on a 15 s freshness stamp
(`~/.reso/last-fetch`); if the stamp is older it runs a **bare, untimed** `git fetch` over
**SSH** (`git@github.com:renchris/reso-management-app.git`), and `~/.ssh/config` has **no
`ConnectTimeout`**. Proof it is unbounded:
```
GIT_SSH_COMMAND='sleep 6 && false' git fetch origin main   → 12,064 ms
```
(git retries the transport, so a 6 s stall costs 12 s.) A black-holed network costs the full
TCP connect timeout, per retry.
**Fixable without losing the guarantee:** the fetch exists only to make `origin/main` current
for `refresh_slot`. The background `ensure` runner already fetches every 2–5 min
(137 `pool-ensure` entries in `~/.reso/worktree-pool.log`). Wrap it —
`timeout 3 git fetch origin main || log "fetch skipped"` — the existing `else` branch already
handles failure ("using last-known origin/main"). Cost of a stale-by-minutes `origin/main` on a
claim is one extra background refresh; cost of the current code is an unbounded launcher hang.

### 3f `pnpm install --frozen-lockfile` — 11–14 s **first touch per slot**, 0.32 s warm
Reproduced on three independent slots: 12,505 ms (slot 2), 14,034 ms (slot 3), **11,022 ms with
`--offline`** — so it is **not network**, it is local work (verify/relink of the ~1.4 GB isolated
store) that is fast only once the OS page cache is warm.
**Fires only when `head != origin/main`** at claim time. Field evidence says this is *rare*: the
pool log has 137 `ensure` runs and only **15 `reset` lines**, all inside background `ensure` —
the replenisher normally absorbs it. But it is on the operator's critical path whenever they land
a commit and relaunch inside the replenisher's gap.
**Fixable:** in `cmd_claim`, prefer a slot that is *already at* `origin/main` and only fall back
to a stale slot after exhausting current ones (the loop currently takes the first live+clean slot
and refreshes it in place). That converts the worst case into a slot-selection preference at zero
correctness cost.

### 3d `db-ensure.sh` — 266 ms on **every** claim, and 3h `prepare-cached.sh` — 204 ms
Both are template copies; small, but they are pure re-assertion of state the background `ensure`
already established. Backgroundable if the DB isn't needed in the first second of a session.

### 1a `claude-accounts --route` — 75 ms, and it is essentially all Python interpreter startup
Cache HIT (75 ms) and cache MISS/abstain (71 ms) cost the same, which pins the cost to
`python3` start, not to the work. **Its worst case is proven bounded**: with the single-flight
lock held by a foreign process it still returned in 69–113 ms, because
`bin/claude-accounts:1861` raises `CacheOnlyUnavailable` *before* touching the lock when
`--max-wait 0`. **The documented 240 s lock ladder is structurally unreachable from the launcher** —
that hypothesis is refuted.

### 5 `_cc_sync_account` — 26 ms (same-account) / 47 ms (cross-account). **Yes, it redoes done work.**
It re-walks all **337** entries of `~/.claude` on every launch (`for e in "$src"/*(ND)`,
`config-mirror.zsh:88`), plus a second dangling-link reap pass over the destination's **440**
entries, plus — for a cross-account dir (`~/.claude-tertiary` etc., whose isolate set keeps
`projects`) — `_cc_sync_memory_mirror` over **366 project slugs** (152 ms of the xtrace's 254 ms
in-shell total). Every one of those is already a correct symlink; the work is pure idempotent
re-assertion.
**It is also the least worth optimising**: 26–47 ms is <2.5 % of the primary-checkout budget and
the SessionStart hook re-asserts it anyway. Leave it; note it only because the brief asked.

### 7 `cc-close-attrib` — ~110 ms
Bash wrapper that must NOT `exec` (it needs `wait` for the exit code — see its header). Cost is a
`mktemp` + hard link + `tee` process setup. Not removable without losing crash attribution.

### 0 shell startup — 310 ms, and only for a NEW pane
`compinit` (456 ms instrumented / ~150 ms real) and oh-my-zsh's `is_update_available` (119 ms)
dominate. If the operator types `claude` into an existing pane, none of this is felt.

---

## 5. What is NOT on the critical path (checked, not assumed)

- **`--assign` is genuinely detached**: `( "$bin" --assign … & )` costs **2.6 ms** to fork vs
  **101–180 ms** run in the foreground. `claude-launcher.zsh:84` is correct.
- **The `--route` single-flight lock** cannot block a launch (§4 above).
- **`_cc_lib _cc_resume_pin`** (0.5 ms) and **`_cc_launcher_map`** (0.1 ms) are noise.
- **`_cc_route_check` is a no-op (8 ms) unless cwd is the reso primary checkout** — it requires
  `.git` to be a *directory* AND `basename == reso-management-app` (`~/.zshrc:106`). Every session
  already inside a linked worktree pays nothing.

---

## 6. Adversarial pass — the three things I nearly missed

1. **"The launcher is silent for the whole wait" — it isn't, and that is a free diagnostic.**
   `_wt="$(_cc_route_check)"` captures **stdout only**; the pool script logs to **stderr**, so the
   operator sees `→ worktree-pool: claimed slot N → cc-HHMMSS-PID` at the *end* of the claim, and
   `◆ routed → nextN` (`claude-launcher.zsh:112`, TTY-gated) at ~100 ms.
   **Ask the operator where the silence sits:** if `claimed slot N` appears fast and the wait
   follows → post-exec, R3 is exonerated. If the wait precedes that line → it is the fetch or the
   pnpm refresh, and this document has the fix.
2. **I assumed the pool-refresh path was the likely cause; the log refutes it.** 15 resets across
   137 `ensure` runs (`~/.reso/worktree-pool.log`), all in background. Without checking that I
   would have reported a 13–16 s "typical" that is actually rare.
3. **I assumed a cold cache would be slow.** It is not — `--max-wait 0` abstains in 71 ms and the
   launcher falls back to the pinned account. The cold-cache hypothesis in the brief is refuted.

**Still-open uncertainty:** every number here was taken on a machine with 3 of 10 pool slots
claimed and light load. Under a 10-session wave the git/pnpm figures will be worse; I did not
measure under load.

---

## 7. Commands (reproduce)

```bash
# harness
cat /tmp/r3-bench.zsh
zsh -lic 'source /tmp/r3-bench.zsh; bench sync_next 5 "_cc_sync_account $HOME/.claude-next"'

# router, incl. lock-held control
zsh -lic 'source /tmp/r3-bench.zsh; bench route 7 "$HOME/.claude/bin/claude-accounts --route interactive --max-wait 0 --max-age 600"'

# fetch, and the unbounded proof
cd ~/Development/reso-management-app && git fetch origin main
GIT_SSH_COMMAND='sleep 6 && false' git fetch origin main      # 12,064 ms

# pnpm first-touch vs warm  (run inside a pool slot)
cd ~/Development/.worktrees/wt-pool-3 && CI=true pnpm install --frozen-lockfile   # 14,034 ms then 335 ms

# end-to-end
cd ~/Development/reso-management-app && rm -f ~/.reso/last-fetch && zsh -lic 'claude --version'   # 2,713 ms
cd /tmp && zsh -lic 'claude --version'                                                            #   688–1,064 ms

# whole-chain xtrace (note: `emulate -L zsh` in the router bodies silently disables XTRACE,
# so the trace under-counts — subprocess timing above is the authority)
cd /tmp && zsh -lic 'setopt xtrace; PS4="+%D{%s.%6.}|%N:%i> "; claude --version' 2>/tmp/r3-trace-on.err
python3 /tmp/r3-parse.py /tmp/r3-trace-on.err
```
