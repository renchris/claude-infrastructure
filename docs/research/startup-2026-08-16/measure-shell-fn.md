# AXIS: shell-fn — the zsh entrypoint layer (Enter on `claude` → exec of the binary)

Measured 2026-08-16 on chrisren's macOS box, ~24 live Claude sessions concurrent (noisy).
Read-only on live config: no edit to ~/.zshrc, ~/.claude*/settings.json, ~/.claude.json, or any hook.

## 0. STRUCTURAL CORRECTION TO THE BRIEF (before any timing)

The brief's ground truth says `claude()` → `_cc_route_config_dir` → `_cc_charge_on_commit` →
`_claude_pinned` → `~/bin/claude-latest`. The first three are right; **the last is wrong for
`claude`**. Chain as it actually exists today:

- `~/.zshrc:701` (LAST line of the rc) sources `~/.claude/lib/claude-launcher.zsh`
  → `/Users/chrisren/Development/claude-infrastructure/lib/claude-launcher.zsh` (252 lines).
- That lib's `_cc_install_router` **snapshots the rc's `claude()` into `_claude_pinned`** and
  **redefines `claude()`** as the router. So the live `claude` is the LIB's function, not `~/.zshrc:451`.
- Router body (lib:174-207): `_cc_route_config_dir` → (if routed) print `◆ routed → nextN`,
  `_cc_charge_on_commit`, then `CLAUDE_CONFIG_DIR=… _claude_pinned "$@"` inside an `always` block.
- `_claude_pinned` == `~/.zshrc:451-503`: `_cc_route_check` → `_cc_lib _cc_resume_pin` →
  `_cc_sync_account` → `_cc_tlid` → **`$HOME/.claude/bin/cc-close-attrib "$HOME/.claude-220/node_modules/.bin/claude" …`**
- `~/bin/claude-latest` is reached only by `claude-prev` / `claude-prev2..4` (`~/.zshrc:173,175`),
  the STABLE 2.1.114 track. **It is NOT on the `claude` path.** Also note `~/.zshrc:498/501` pins
  `~/.claude-220`, while the rc header comment above it still says `~/.claude-219` — comment is stale.
- `_cc_route_check` is ALSO shadowed: the lib redefines it (lib:230-252) after the rc's copy (rc:106),
  and the lib is sourced last, so the LIB copy wins in every new shell (R6 fix, 2026-08-12).

Verification commands:
```
grep -n "claude()" ~/.zshrc                       # 451
tail -1 ~/.zshrc                                   # sources ~/.claude/lib/claude-launcher.zsh
cd /tmp && zsh -ic 'typeset -f _claude_pinned | grep -n "claude-latest\|claude-220\|cc-close-attrib"'
  → 37: local _bin="$HOME/.claude-220/node_modules/.bin/claude"
  → 45: … "$HOME/.claude/bin/cc-close-attrib" "$_bin" …          (no claude-latest anywhere)
cd /tmp && zsh -ic 'typeset -f _cc_route_check | grep -n "reso/bin"'   → lib copy wins
```
`~/.claude/bin/cc-close-attrib` says so itself (header, lines 29-33): *"claude-next / -2/-3/-4,
claude-fable*, claude-desk* and every handoff-fire spawn exec the versioned binary through THIS
wrapper and never through bin/claude-latest"*.

## 1. Bench harness

`/tmp/sf-bench.zsh` — `zmodload zsh/datetime`, `EPOCHREALTIME` around an `eval`, n≥5, reports
min/median/max plus every raw sample. Run inside `zsh -ic` (interactive, so the rc + launcher lib
are loaded exactly as the operator's pane has them). Machine had ~24 live Claude sessions.

## 2. zsh startup (is it even on the path?)

```
cd /tmp && for i in 1 2 3 4 5; do /usr/bin/time -p zsh -i -c exit; done
  real 0.56 (cold) 0.19 0.19 0.20 0.19        → median 190 ms
cd /tmp && for i in 1 2 3 4 5; do /usr/bin/time -p zsh -l -i -c exit; done
  real 0.53 (cold) 0.21 0.20 0.22 0.26        → median 215 ms
cd /tmp && for i in 1 2 3; do /usr/bin/time -p zsh -lic true; done
  real 0.26 0.24 0.23                         → median 240 ms   (R3's apples-to-apples form)
cd /tmp && for i in 1 2 3; do /usr/bin/time -p zsh -l -c exit; done    (NON-interactive)
  real 0.02 0.02 0.02                         → the 41KB rc is ~all interactive-only
```

zprof (`zsh -i -c 'zmodload zsh/zprof; source ~/.zshrc; zprof'`):
```
 1)   1  191.76  51.87%  compdump
 2) 842   72.93  19.73%  compdef
 3)   1  359.58  18.10%(self 66.92)  compinit
 4)   2   28.56   7.73%  compaudit
 6)   1    3.52   0.95%  omz check_for_upgrade.sh:126
11)   1    0.17   0.11%  _cc_install_router
```
⚠️ CAVEAT, stated because it changes the conclusion: this profile DOUBLE-SOURCES the rc, which
invalidates the completion dump and forces a `compdump` rebuild (191 ms) that a normal shell does
not pay. The honest number is the wall clock above: **190–215 ms**, not 360 ms. Everything reso/CC
adds to shell start is noise (`_cc_install_router` 0.17 ms).

**PATH CLASSIFICATION — zsh startup is CONDITIONAL, and both cases are real:**
- Operator types `claude` into an ALREADY-RUNNING pane → **0 ms. NOT on the critical path.**
- Any **dispatched fire / new pane** → **BLOCKING ~200 ms**. `scripts/handoff-fire.sh:905-906`
  records the measurement that forces it: *"`bash -lc 'type -t claude4'` → not found; `zsh -l -c`
  → not found; only `zsh -l -i -c` resolves it"* — so every fired pane pays a full interactive rc.

## 3. Per-helper medians (cwd = /tmp, i.e. NOT the reso primary)

```
cd /tmp && zsh -ic 'source /tmp/sf-bench.zsh; bench "<label>" <n> "<cmd>"'
```

| helper | n | min | **med** | max | path class |
|---|---|---|---|---|---|
| `_cc_route_config_dir` (whole) | 7 | 74.2 | **76.0** | 84.4 | BLOCKING |
| ├ `claude-accounts --route interactive --max-wait 0 --max-age 600` | 7 | 72.2 | **75.2** | 80.4 | BLOCKING |
| ├ `python3 -c pass` (interpreter floor, for reference) | 5 | 23.1 | **23.4** | 24.6 | — |
| └ `_cc_launcher_map` | 5 | 0.1 | **0.1** | 0.3 | BLOCKING |
| `_cc_charge_on_commit` foreground | 5 | 3.5 | **4.3** | 5.7 | BLOCKING |
| └ its `sleep 5; --assign` subshell (`&!`) | — | — | — | — | **BACKGROUNDED — 0** |
| `_cc_route_check` (non-git / linked worktree, early return) | 7 | 7.5 | **7.9** | 8.2 | BLOCKING |
| `_cc_lib _cc_resume_pin cc-resume-shell.sh` | 5 | 0.4 | **0.4** | 0.5 | BLOCKING |
| `_cc_resume_pin <cfg> --version` | 5 | 0.1 | **0.1** | 0.1 | BLOCKING |
| `_cc_sync_account ~/.claude-next` (same-account) | 5 | 26.6 | **27.6** | 67.3 | BLOCKING |
| `_cc_sync_account ~/.claude-secondary` (cross-account = what routing picks today) | 5 | 52.5 | **54.1** | 80.9 | BLOCKING |
| `_cc_tlid` (2× `git rev-parse` + `basename` + fork) | 7 | 20.7 | **21.6** | 22.0 | BLOCKING |
| `cc-close-attrib` wrapper overhead (222.4 − 150.1, same flags both sides) | 5 | — | **~72** | — | BLOCKING |

## 4. End-to-end, and the split between shell layer and binary

```
cd /tmp && env -u CLAUDE_CONFIG_DIR -u CC_ACCOUNT_PINNED zsh -ic 'source /tmp/sf-bench.zsh; bench …'
```
(`env -u CLAUDE_CONFIG_DIR` matters: inside a live CC session that var IS exported, and the
router's guard `[[ -z "${CLAUDE_CONFIG_DIR:-}" ]]` then short-circuits — a first measurement pass
silently measured a NON-routing launch and under-reported the router by ~100 ms.)

| stage | n | min | **med** | max |
|---|---|---|---|---|
| bare binary `--version` | 5 | 69.1 | **70.4** | 76.7 |
| binary `--permission-mode auto --model claude-opus-5 --effort high --version` | 5 | 145.8 | **150.1** | 153.3 |
| `cc-close-attrib` + binary, same flags | 5 | 211.7 | **222.4** | 234.0 |
| `_claude_pinned --version` (no router) | 5 | 263.9 | **282.6** | 317.5 |
| `claude --version` (FULL chain, routing ARMED, cwd=/tmp) | 5 | 378.5 | **386.9** | 401.8 |

⇒ **shell-fn layer = 386.9 − 150.1 = ~237 ms BLOCKING** (median), of which ~72 ms is
`cc-close-attrib`. Component sum checks out: 76 + 4 + 8 + 0.5 + 54 + 21.6 + 72 = **236 ms**.

xtrace decomposition of the pinned body (`setopt xtrace; PS4="+%D{%s.%6.}|%N:%i> "`, aggregated
per function over 5,941 traced lines, total traced span 99 ms — xtrace inflates, use it for SHAPE):
```
57.0 ms  3870 lines  _cc_sync_config_mirror     ← the symlink re-assertion walk
28.5 ms  1990 lines  _cc_linktarget             ← called from it
14.8 ms    24 lines  _claude_pinned (own)
 0.5 ms          _cc_lib · 0.3 _cc_resume_pin · 0.1 _cc_sync_memory_mirror / _cc_oauth_token_env
```

## 5. NETWORK / QUOTA-API — answered: NONE on this layer

`claude-accounts` DOES reach `api.anthropic.com/api/oauth/usage` (header line 7; `urllib` at
:645-664, 12 s timeout) and DOES fork `/usr/bin/security find-generic-password` (:358) — but only
on the SWEEP path. The launcher passes `--max-wait 0`, which is cache-only by construction
(`:2477-2480` raises `CacheOnlyUnavailable` *before* the lock and before any fetch).

Three independent proofs, all today:
1. Code: `cache_only = max_wait is not None and max_wait <= 0` (:3970); `--fresh` + `--max-wait 0`
   is a hard usage error (:3974).
2. Differential with an unusable proxy — if a request were made this would stall or fail:
   `https_proxy=http://127.0.0.1:1 http_proxy=… claude-accounts --route …` → med **73.4 ms**
   vs **72.3 ms** unproxied (n=5 each). No difference.
3. Forced cache MISS is CHEAPER, not slower: `--max-age 0` → med **68.7 ms**, `rc=3`,
   `route-meta: cache=absent mode=cache-only waited_ms=0`, stdout `none`. It abstains; the caller
   falls back to the pinned account.

So the 75 ms is **python3 process start + imports** (floor `python3 -c pass` = 23 ms), not I/O.
Live cache today: `quota_age_s=168 cached=1` → hit, picked `next2`.

## 6. 🚨 THE UNBOUNDED ARM — reso PRIMARY cwd, and the pool is EXHAUSTED RIGHT NOW

`_cc_route_check` is an 8 ms no-op unless `basename $(git rev-parse --show-toplevel)` ==
`reso-management-app` AND `.git` is a directory (i.e. the PRIMARY checkout, not a linked
worktree). There it runs `bash ~/.reso/bin/worktree-pool.sh claim cc-HHMMSS-$$` **synchronously,
capturing stdout** — nothing prints while it runs.

R6 (2026-08-12) made the claim fast by removing `fetch_guarded` + `refresh_slot` from it
(re-read `cmd_claim` today: confirmed gone, and the fast path is real). **But R6's 200 ms assumes a
FREE slot exists. Today none does:**

```
timeout 60 bash ~/.reso/bin/worktree-pool.sh status
  pool size 10 · trunk origin/main @ 8fe22bdbc
  slot 1..10: ALL "CLAIMED/FOREIGN"        (8 of them carry launcher branches cc-HHMMSS-PID)
free=0; for i in $(seq 1 10); do b=$(git -C ~/Development/.worktrees/wt-pool-$i branch --show-current);
        [ "$b" = "pool/slot-$i" ] && free=$((free+1)); done; echo $free
  → live/free slots = 0 / 10
```

`cmd_claim` then scans 2 passes × 10 slots (`slot_live` = one `git branch --show-current` fork per
slot) and falls through to `new-worktree.sh`:
```
log "pool empty — falling back to cold new-worktree.sh"
( cd "${MAIN}" && bash "${SCRIPT_DIR}/new-worktree.sh" … )
```
whose line 70 is `CI=true pnpm install --frozen-lockfile`.

Measured today (read-only, no claim taken):
```
for r in 1 2 3; do  # the wasted 2-pass scan before the fallback
  time { for i in {1..10}; do for p in 1 2; do git -C ~/Development/.worktrees/wt-pool-$i branch --show-current; done; done }
  → 132.7 / 142.7 / 186.3 ms          (median 142.7 ms, pure waste on an exhausted pool)
git -C ~/Development/reso-management-app worktree list --porcelain  → 12.1 / 12.4 / 11.4 ms
git -C ~/Development/reso-management-app rev-parse --show-toplevel  →  6.6 /  6.5 /  6.2 ms
```
**The cold `new-worktree.sh` leg I did NOT measure today — UNKNOWN, deliberately.** Running it
would create a worktree + branch in the operator's primary checkout while ~24 sessions are live.
Bounds from evidence rather than guess: `worktree-pool.sh:18-20` documents 20–30 s, and R3
measured this repo's `pnpm install --frozen-lockfile` first-touch at **11.0–14.0 s** (3 slots) —
and that measurement was on a slot with a warm store; a brand-new worktree has none.

Compounding, from `~/.reso/worktree-pool.log` (last 3 ensure runs before 14:38 today):
```
→ worktree-pool: slot 7: unprovisioned (node_modules missing) — provisioning
→ worktree-pool: slot 7: pnpm install failed
 ERR_PNPM_RECURSIVE_EXEC_FIRST_FAIL  Command failed with ENOENT: panda codegen
```
The background replenisher cannot currently re-provision slot 7 — `panda` is missing from that
slot's bin dir — so the pool cannot self-heal back to a free slot from that side.

## 7. Prior-art re-verification (every claim re-measured today)

| prior claim | source | today | verdict |
|---|---|---|---|
| `claude()` → … → `~/bin/claude-latest` | brief ground truth | binary is `~/.claude-220/…` via `cc-close-attrib`; claude-latest is the `claude-prev` (2.1.114) track only | **STALE / WRONG for `claude`** |
| shell startup 310 ms | R3 §2 row 0 | `zsh -lic true` = **240 ms** | improved, roughly holds |
| compinit dominates startup | R3 §4 | holds in shape; the 360 ms zprof figure is a double-source artifact | holds w/ caveat |
| `_cc_route_config_dir` 96 ms | R3 §2 row 1 | **76 ms** | holds (better) |
| `--route --max-wait 0` ≈ 75 ms, cache hit == miss | R3 §2 1a/1b | **75.2 / 68.7 ms** | **HOLDS exactly** |
| 240 s lock ladder unreachable from the launcher | R3 §4 | code re-read: `CacheOnlyUnavailable` before the lock | **HOLDS** |
| `--assign` genuinely detached (2.6 ms fork) | R3 §5 | now via `_cc_charge_on_commit`, fg **4.3 ms**, work `&!` after 5 s | **HOLDS** |
| `_cc_route_check` 8.2 ms off the primary | R3 §2 row 2 | **7.9 ms** | **HOLDS** |
| `_cc_lib` 0.5 ms | R3 §2 row 4 | **0.4 ms** | **HOLDS** |
| `_cc_sync_account` 26.5 / 47.3 ms | R3 §2 row 5 | **27.6 / 54.1 ms** | holds (cross-account slightly worse) |
| `_cc_tlid` 19.9 ms | R3 §2 row 6 | **21.6 ms** | **HOLDS** |
| `cc-close-attrib` ~110 ms | R3 §2 row 7 | **~72 ms** (measured with identical flags on both sides, which R3 did not do) | refined down |
| R6: claim no longer fetches / installs | R6 table | `cmd_claim` re-read — confirmed removed | **HOLDS** |
| R6: claim = 200 ms, e2e from primary = 940 ms | R6 table | **UNVERIFIABLE today — 0/10 free slots ⇒ cold path, not the 200 ms path** | **STALE in practice** |
| R3: "chain ≈ 250 ms from an ordinary cwd" | R3 §3 | **237 ms** | **HOLDS** |

## 8. What is NOT on the critical path (checked, not assumed)

- `_cc_charge_on_commit`'s ledger write: `( sleep 5; …--assign… ) &!` — BACKGROUNDED, 0 ms.
- Any network or keychain access — structurally excluded by `--max-wait 0` (§5).
- `_cc_launcher_map`, `_cc_lib`, `_cc_resume_pin` — 0.1–0.4 ms each, noise.
- zsh rc for an existing pane — 0 ms (but ~200 ms for every fired pane, §2).

## 9. Dead ends / things I got wrong first

- First e2e pass measured `claude --version` at 290 ms and `_claude_pinned --version` at 309 ms —
  i.e. the router appearing to cost NEGATIVE time. Cause: I was inside a live CC session where
  `CLAUDE_CONFIG_DIR` is exported, so the router's own guard disabled routing. Fixed with `env -u`.
- Compared `cc-close-attrib --version` against `binary --version` and got a 72 ms wrapper cost that
  did not reconcile with the totals; the gap was the binary itself, which costs 70 ms bare but
  **150 ms** once `--permission-mode/--model/--effort` are parsed. Both sides must carry the flags.
- `grep -c "claim" ~/.reso/worktree-pool.log` → 0. The log only carries `pool-ensure` sections;
  claims are not logged there, so claim frequency had to be inferred from the slot BRANCH NAMES
  (`cc-HHMMSS-PID`, which only `_cc_route_check` mints) — 8 of 10.
