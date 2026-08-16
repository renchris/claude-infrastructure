---
status: in-progress
---

# START_LATENCY_ROUTER — `claude1` pin + auto-routed `claude`, at a start cost that cannot regress

Owner: session a28e8b9c · Opened 2026-08-10 · Backlog `492b95cbac72`
Base: `origin/main` @ `c51ee3ec` · Worktree `.worktrees/start-latency` · Branch `feat/start-latency-router`

**Scope (frozen):** make `claude1` the pinned account-1 entrypoint and bare `claude` auto-route to
the best account, at a 100th-percentile start cost that never inherits the sweeper's tail —
researched to conviction, implemented, landed, live.

---

## Phase 0 — Orchestration

**Execution locus per wave.**

| Wave | Locus | Why |
|---|---|---|
| W0 research (12 axes) | **S** — parallel research subagents | done; reports in `~/.claude/research-artifacts/start-latency-2026-08-10/` |
| W1 `bin/claude-accounts` (query mode + parallel sweep + thread-safety fixes) | **L** — lead inline | one file, one coherent diff, and every change is interlocked with the measured races in D. Splitting it invites a partial patch that ships a race. |
| W2 shell + SSOT + plist + migration + tests | **L** — lead inline | small surface, but each piece is C10-adjacent and must agree with W1's contract exactly |

Lead context budget: hold ≥40% for the land + live verification. Succession point: after W1 lands.

**Dependency graph.** W1 blocks W2 (the shell calls the contract W1 defines). Parity precondition
(P0 below) blocks the *switch*, not the build.

---

## The decision, in one line

Keep **one arbiter** (`bin/claude-accounts`) and make its *read* path incapable of blocking —
rather than moving routing policy into shell for the last 100ms. Justification is measured, below.

---

## What the research settled

### Confirmed, load-bearing

| # | Finding | Evidence |
|---|---|---|
| F1 | **`claude1` is necessary, not cosmetic.** handoff-fire resolves account `next`'s launcher to bare `claude` (`scripts/handoff-fire.sh:6070`) then charges `--assign next` (`:6087`). If `claude` re-routes at exec, fires *assigned* to next land elsewhere — spread math inverted. | G/S1 |
| F2 | **The rename moves no census.** The zsh function name never appears in argv; all 12 live sessions show the binary path. 12 named `argv[0]=claude` consumers are safe by construction. | E/C4 |
| F3 | **`aliases` is a config-dir-basename alias, not a launcher alias** — consumed only by `cc_acct_name_for_dir_basename`. Keeping `claude` there rescues nothing; after the flip `cc_acct_dir_for_name claude` returns unknown. | E/C2 |
| F4 | **The warm read path is already lock-free**, 104.9ms in-process: import 69.7 · load_cfg 30.2 · cache_read 0.9 · apply_assignments 1.8 · apply_burn 1.8 · ranked 0.1. Blocking happens only on a cache MISS. | B/§1 |
| F5 | **The tail is real and bounded at 240s + exit 5.** miss → `lock_wait_s`=5 → grace read (600s) → else a second bounded flock at `fresh_lock_wait_s`=240 → `FreshLockWedged` → exit 5. Holder's own comment names the worst case as MINUTES. | B/§1, G/S13 |
| F6 | **600s staleness is free.** At ≤10min the stale pick is now-excluded in 0.8% of pairs (median score-ratio 1.000). Across 931 recorded decisions the grace band has never been entered (max age 89s). | B/(c) |
| F7 | **Burst spread already survives a cached read.** `record_assignment` is dispatched *before* the `get_data` anchor (`:2924-2942`); `assignment_counts` reads the ledger at invocation (`:1231-1252`); `apply_assignments` runs after `get_data` regardless of `cached` (`:2946-2948`). | B/(d), G/(a) |
| F8 | **The sweep's biggest term is not the probes.** `working_concurrency` 865ms · `concurrency` ps 221ms · 4 serial probes 1350ms · load_cfg 44ms = 2480ms. `working_concurrency` is consumed *after* the loop (`collect():1033`) — a free 5th parallel task. Measured 5-way: **340–674ms**. | D/§1 |
| F9 | **Concurrency activates two latent defects.** `_save_rejected():735` names its temp `f"{path}.{os.getpid()}.tmp"` — identical across threads, so two saves rename the same temp into place. And the retry ladder has no jitter, so four simultaneous 429s retry in lockstep. | D/§2, §5 |
| F10 | **The 429 branch emits no `log_event`.** 5,413 log lines, zero throttle entries — because the instrument does not exist, not because it never fired. | D/§5 |
| F11 | **No prior art.** ACCOUNT_ROUTING_V2 (M1–M7, all landed) is entirely about *which account gets picked*, never *how fast the picker answers*. No milestone, remainder or AC mentions start latency, launcher naming, cache warming or parallel sweep. | H/§1 |
| F12 | **`~/.zshrc` and any new launchd plist are C10 — an agent may not self-activate either.** A plist merely copied into `launchd/` activates at next login; `expect=staged` only suppresses `launchctl bootstrap` now. Genuinely-staged jobs go in `launchd/staged/`. | I/§0 |

### Refuted (recorded so they are not re-litigated)

| Claim | Verdict |
|---|---|
| "Auto-routing scatters project memory across 4 config dirs" (J/4) | **REFUTED.** `memory` is a symlink to `~/.claude/memory` in all four dirs; the isolate-sets (`lib/config-mirror.zsh:38-42`) keep `projects`/`sessions`/`history.jsonl` per-account but never `memory`. |
| "Account 1 silently skips 15 configured hooks" (lead's own first reading) | **REFUTED.** Hook commands are absolute `~/.claude/hooks/…`, so they resolve to the shared dir whatever the config dir. The 53-vs-75 per-dir file count is a red herring. |
| "A cached verdict reintroduces the burst-stacking M7 fixed" (J/2) | **REFUTED given we cache ROWS, not a winner** — see F7. It would be true of a bare winner name. |
| "The daemon could overwrite the assignment ledger" (G/(a)) | **REFUTED.** Different files: `~/.claude/logs/account-assignments.jsonl` vs `/tmp/claude-accounts-cache.json`. |

### The finding that changes the objective — **S8, horizon mismatch**

`score = headroom/T^2` is deliberately deadline-DOMINANT (`bin/claude-accounts:1186-92`) because it
was built for **short dispatched fires**: it prefers the account whose quota is about to strand.
An interactive desk lives for hours or days. Reusing it for bare `claude` places the operator's
long session **nearest exhaustion** — manufacturing the 5-hour wall the feature exists to avoid,
and reading as an ordinary limit hit with no signal that routing caused it.

**Therefore the interactive lane is a distinct objective, not a reuse:** maximise *survival*
(absolute headroom × runway), not minimise stranding. Implemented as `--route interactive`
alongside `general`/`fable`, sharing every exclusion (cliff, S_CUT, kmax) and differing only in
the score. Two further interactive-lane rules fall out:
- **never yield the cliff term** (G/S10 — `ranked()` re-ranks without it when the drain empties the
  set; right for dispatch, wrong for a human, because `invalid_grant` has no reset to wait for);
- **hysteresis** — keep the incumbent unless beaten by a margin (G/S9: routed launches move burn,
  which feeds `record_utilization`, which feeds the next ranking).

---

## P0 — Precondition: hook-set parity

Measured: 74 configured hook commands in accounts 2/3/4, **69 in account 1**, intersection 69.
Account 1 alone lacks `cc-unattended-ask-guard.sh`, `desk-brief-inject.sh`, `session-beat.sh`
(prompt + stop), `session-deregister.sh`. Routing makes *which guards run* a function of quota
(G/S2). The safe direction is bringing account 1 up to the superset, which is a strict improvement
independent of routing. Related known item: config-mirror never heals a forked settings.json.

---

## Build

### W1 — `bin/claude-accounts`

1. **`--max-wait S` / `--max-age S`** — global modifiers, positional value, malformed ⇒ exit 64,
   defaults = today's SSOT constants so every existing caller stays byte-identical. **No new exit
   code**; absent/stale/corrupt ride `route-meta:` as `cache=`, `mode=`, `waited_ms=`, `k_src=`.
2. **Never-block read path**: with `--max-wait 0` the call returns from cache or abstains — never
   `_acquire_lock`, never `collect()`, never `heal()`.
3. **Skip `resolve_claude_bin` when the mode cannot heal** (`:207`) — 16ms and a 10s hang surface
   on a path advertised as non-blocking.
4. **`--route interactive`** — survival-scored lane, no cliff yield, hysteresis margin.
5. **Parallel sweep**: `ThreadPoolExecutor`, `executor.map` (order-preserving), 5 tasks —
   4 probes + `working_concurrency`. `concurrency()` stays serial (its `k_live` gates every heal).
   Pre-warm `SSL_CTX` and `urllib._opener` in the main thread. `_HEAL_GATE = Semaphore(1)`
   (`claude auth login` is an opaque binary; unverified ⇒ do not assert safe). Ledger writes stay
   single-threaded.
6. **Thread-safety fixes** (F9): `_REJECTED_LOCK` around load→mutate→save; unique temp names at
   `_save_rejected():735` and `save_lastgood():782`; jitter in both `fetch_usage` sleeps.
7. **Instrument the 429** (F10): `log_event` on the poll-throttle branch, in the same diff.

### W2 — shell, SSOT, daemon, tests

8. `accounts.json` `accounts[0].launcher` → `claude1`; regenerate via `scripts/gen-account-map.sh`
   (never hand-edit the generated map — `tests/handoff-fire-launcher-map.bats:185` is the drift guard).
9. `~/.zshrc`: shared `_claude_launch` body; `claude1`/`claude2`/`claude3`/`claude4` pinned wrappers;
   `claude` routes **only** when `CLAUDE_CONFIG_DIR` is unset **and** not a resume **and** no pin.
   `handoff-fire` exports `CC_ACCOUNT_PINNED=1`. Provenance token on every launch — `routed next4
   (cache 57s)` vs `fallback next (no cache)` — so a dark router cannot masquerade as a pick (G/S5).
   Must not add a fourth `~/.zshrc` binary-path parser (`tests/account-fact-derivation.bats:310-342`).
10. Keep-warm producer — **bounded**: G/S6 measures the risk that a sub-90s warmer manufactures the
    outage (429 → `row["error"]` → data-unavailable → `cc-route` exit 3 = fire-blind refusal
    fleet-wide). Cadence, heal polarity (G/S7: a `no_heal` cache is refused to heal-wanting callers
    when any row is BAD_AUTH) and jitter per report C. Ships **`launchd/staged/`** + a
    `fleet.manifest` row, never auto-activated.
11. `migrations/NNNN-start-latency-activation.sh`, `# migration-class: c10`, precedent
    `migrations/0008-auth-timeseries-activation.sh:1-6` — files the operator step.
12. Tests: extend `tests/claude-accounts-core.bats` (contract + exit codes), a new arm in
    `tests/claude-accounts-fresh-lock-bound.bats` (never-block), `tests/handoff-fire-launcher-map.bats`
    (drift), plus a control that FAILS pre-fix for each of F9's two races.
13. `scripts/growth-coverage.conf` row for any new append-only surface.

---

## Binding decisions from C (keep-warm) and F (shell)

| # | Decision | Why (measured) |
|---|---|---|
| C1 | **New label `com.claude.accounts-keepwarm`** — never an extension of `com.claude.auth-timeseries` | that job is NOT-LOADED/`staged`, and its plist declares as an auditable property *"NO network call of any kind"* (`launchd/com.claude.auth-timeseries.plist:21-26`) which a 4-fetch keep-warm sweep destroys. Their cadences are also justified by different physics (300s sampling vs a 90s TTL). |
| C2 | **The producer is a FLAG on `bin/claude-accounts`, not a new `scripts/*.sh`** | `~/.claude/bin/claude-accounts` already exists as a symlink into the checkout, so a flag is an EDIT that rides it. A new script is an ADD with no link ⇒ `LIVE_ADDS` breach and a plist that fails every tick — the exact trap `migrations/0008` was written about. |
| C3 | **`StartInterval 60`** | TTL 90s (`accounts.json:23`) − sweep 1.85–2.53s ⇒ worst-case consumer age **62.5s**, margin 27.5s. 75s leaves 12.5s — smaller than the variance one `fetch_usage` retry adds (+1s sleep, ≤12s timeout, `:493-509`). Fleet precedent at 60: `session-search-sweep`, `capacity-alarm`. |
| F1 | 🚨 **The pin travels as an ARGUMENT, never an env var.** `CLAUDE_CONFIG_DIR` is present in the env of every process a session spawns (measured), so "route when unset" is dead on every automated path. Seam: `_claude_launch <config-dir> [argv…]` ← `claude1..4` pinned wrappers ← `claude` router. | supersedes the lead's earlier `CLAUDE_CONFIG_DIR`-unset proposal |
| F2 | **Keep zsh prefix assignment, never `export`** | measured: a prefix assignment on a function call does not persist in the caller and *is* exported for the call's duration — which is exactly the desired scope. `export` would leak into later launches in the same shell. |
| F3 | **Declare every local once, at the top** | a bare `local _x` on an already-local name **prints `_x=''` to stdout**; any helper captured with `$( )` then returns a garbage config dir. Rule already recorded at `cc-resume-shell.sh:48-51`. |
| F4 | **`emulate -L zsh` in every launcher function** | `KSH_ARRAYS` corrupts unprotected array code. House style already (`ccr()`). |
| F5 | **Never pipe the router** | `$(cmd \| tail -1)` yields *tail's* rc, so the documented 0/2/3 exit enum becomes unreadable. Capture directly. |
| F6 | **Guard `timeout`** — it is `/opt/homebrew/bin/timeout`, absent under `PATH=/usr/bin:/bin`; degrade to an unbounded call rather than to no routing | measured |
| F7 | **`--no-heal` is mandatory on the launch path** | `heal()` runs `claude auth login` with `timeout=90` **per account** (`bin/claude-accounts:547`) |
| F8 | Launch notice stays ONE line | the statusline already renders the account from `CLAUDE_CONFIG_DIR`/transcript path (`~/.claude/statusline.sh:237-256`), so the notice is confirmation, not the only channel |

Measured by F on the live box: `--route general` **3.02s cold · 0.50s cached-cold-process · 0.10s hot**; `--assign` 0.12s.
Note also (F): `zsh -c` does not see `claude` (NOFUNC) and `bash -lc type claude` resolves a *different*
stock binary at `~/Library/pnpm/claude` (2.0.5) — scripts and hooks never reach the router at all.

## Filed, not absorbed (outside the frozen DoD)

**`probe_provider` is 4.31s of a 4.37s warm `--json` call** — 6 providers, 8 child CLI processes
(`bin/claude-accounts:2990`), uncached and TTL-free, re-run on every invocation. Consumers:
`cc-context:117`, `cc-value:189`, `cc-board:43`, `cc-wave-plan:32`, `cc-blockers:1285`. It is NOT on
the `--route` launcher path (call sites only at `:2874`, `:2990`, `:3130`), so it is out of this DoD —
but it is the larger win on the `--json` path and wants a provider-probe cache (~900s TTL,
invalidated on `providers.json` mtime). Filed separately; declaring start latency "fixed" while this
stands would be a measured false claim (C/§0).

## Outcome (2026-08-11) — DONE, and the biggest win was not the one we set out to get

| # | Shipped | Measured |
|---|---|---|
| `b944be5f` | `lib/config-mirror.zsh` de-forked (`zsh/stat` instead of `$(readlink)` ×3) | `_cc_sync_config_mirror` **1554ms → 25.8ms** (.claude-next), 1473 → 24.5 (.claude-secondary), memory mirror 99 → 23.5. The SessionStart re-run fell **1137ms → 0.03s** with no extra machinery — the double-run was only a problem because each run was 1.1s. 186 links byte-identical; 5-case control + mutant. |
| `e4ddb464` | `--max-wait` / `--max-age` — bounded, non-blocking reads | warm 0.07s; abstain (`none`, rc 3, `route-meta: cache=absent`) 0.07s; no-flag behaviour byte-identical |
| `d45d95f5` | `--route interactive` — the survival lane | discriminates 13.7× on the canonical M7 case; both lanes agree on today's live fleet, so the synthetic pair is what proves it |
| `faeeab24` | `lib/claude-launcher.zsh` + migration 0009 + activation 36 | 15/15 hermetic, no grandfather line |
| `23bbf259` | `--keepwarm` + staged plist + manifest row | found and fixed two silent bugs (below) |

**THE HEADLINE, and it reframes the original question.** `claude --help` measured **1587.7ms** while
the binary alone is **180.8ms** — so ~1407ms was shell prologue, and ONE function was 1075-1554ms of
it. The router was never the start cost; the config-mirror fork storm was, and it was paid at least
twice per launch. J's red-team said "routing is not the launch cost" and was right for a smaller
reason than the real one.

**Two silent bugs the work surfaced**, both of which would have shipped looking healthy:
- `get_data`'s post-lock re-read ignored `grace_s`, which would have made the keep-warm daemon a
  **no-op that logs success** — every tick serving a <90s cache, never sweeping, cache expiring anyway.
- Reformatting the `get_data` call broke a documented **source-patch anchor**; a literal replace that
  matches nothing is a silent no-op, so two tests ran unpatched and failed with an unrelated symptom.
  The patch now asserts it applied (mutant-verified).

**Refuted along the way** (recorded so they are not re-litigated): the lead's own first reading that
account 1 silently skips 15 configured hooks — the commands are absolute `~/.claude/hooks/…` and
resolve to the shared dir; the 53-vs-75 per-dir file count is a red herring. What IS real is small
and bounded: 74 configured hook commands in accounts 2/3/4 vs **69 in account 1**, intersection 69,
account 1 alone lacking `cc-unattended-ask-guard.sh`, `desk-brief-inject.sh`, `session-beat.sh`
(prompt+stop), `session-deregister.sh` (P0 above).

**Process note worth keeping.** Two measurements in this session were nulls from blind instruments:
a `cc-bats` run refused for concurrency read as "0 failures", and an A/B via
`git checkout origin/main -- .` silently staged a sibling's newly-landed files into the worktree.
Both were caught only by asking whether the instrument had actually run.

## Follow-ons — FILED, not forgotten

1. **Parallel sweep** (D's report, complete patch shape). `collect()` is serial; `working_concurrency`
   (865ms) is consumed *after* the loop so it is a free 5th task. Measured 5-way: **340-674ms** vs
   2480ms. Requires `_REJECTED_LOCK`, unique temp names (`_save_rejected():735` uses a pid-only temp,
   identical across threads), `_HEAL_GATE`, SSL/opener pre-warm, and jitter in both `fetch_usage`
   sleeps — plus a `log_event` on the 429 branch, which today emits nothing at all (5,413 log lines,
   zero throttle entries, because the instrument does not exist). Off the interactive critical path,
   which is why it is not in this land.
2. **Provider-probe cache.** ~~`probe_provider` is **4.31s of a 4.37s warm `--json` call**~~ —
   **DONE 2026-08-15, landed `fb1ea5d43`** (backlog `d1068fdf9b6a`). Re-measured before building:
   **3.68s of a 3.7s** run, same shape. Warm `--agents` **0.068s vs 3.24s cold**, `--json` **1.5s vs
   ~4.4s**, render byte-identical cached vs `--fresh`.

   🚨 **The remedy proposed here — "a ~900s cache invalidated on providers.json mtime" — is wrong as
   literally stated, and the mutant proves it.** It reads as caching `probe_provider()`, which cannot
   be done: `pinned_model` is read from the provider's OWN config precisely so a config file governs
   and a remembered value does not, and `installed` must answer for the PATH as it is now. A
   whole-probe cache reds `tests/claude-accounts-providers.bats` "the model pin is read from the
   provider's OWN config", which edits a provider's settings.json between two runs with the registry
   untouched. Only the CHILD PROCESSES are memoised. And keying on providers.json alone — the
   invalidation this bullet names — is also too weak: that mutant reds the binary-identity test,
   reporting an upgraded provider at its old version. The key carries argv + the resolved binary's
   realpath/mtime/size + the registry's mtime/size, with failures at a 60s TTL rather than 900s.

## Open at time of writing

Reports A (start-path census), C (keep-warm design), F (shell code), L (binary boot cost) were
still running. **L governs one decision**: if the binary's own boot dominates by an order of
magnitude, the 105ms warm read needs no further optimisation and the pure-shell verdict file
(K/A) stays rejected on the "one arbiter" ground (G/S4: cached rows carry no scores — scoring is
per-invocation at `:2952-67` — so a shell reader must re-implement `score_general`).
