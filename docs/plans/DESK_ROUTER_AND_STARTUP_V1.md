---
status: open
created: 2026-08-11
branch: desk-router
repo: claude-infrastructure
---

# DESK_ROUTER_AND_STARTUP_V1 — bare `claude` routing, session-start latency, and the startup board

**Status:** research COMPLETE (8 axes + 1 lead-run probe), implementation NOT STARTED.
**Created:** 2026-08-11. **Branch:** `desk-router` (off `origin/main`).
**Research:** `docs/research/R1…R8` in this worktree + `R5b-sessionstart-render-probe.py`.

Scope (frozen): fix bare-`claude` account routing so it matches the operator's stated objective and is
visible before/at launch; cut session-start latency to its floor; and print the `/accounts` board at
session start at zero model-token cost. Land + converge live.

---

## 0. Phase 0 — Agent Team Orchestration

**EXECUTION LOCUS PER WAVE: `S` (dispatched handoff session) for W1–W3, `L` (lead-inline) for W0.**

W0 is three one-line edits with a single test file and belongs on whoever runs first. W1–W3 are
independent code changes in separate files with separate test suites, so each is one dispatched
session per the standing default. The lead holds ≥50% of its window for deciding, not implementing.

| Wave | Locus | Deliverable | Files owned (no overlap) | Gate |
|---|---|---|---|---|
| **W0** | L | Latency: the 240× hook fix | `hooks/lib/task-helpers.sh`, `hooks/session-start.sh` | `tests/` for task-helpers; measure before/after |
| **W1** | S | Routing policy: two-key desk score | `bin/claude-accounts` (`score_interactive` + docstring), `accounts.json` (constants) | `tests/claude-accounts-core.bats` (69) |
| **W2** | S | Observability: `/accounts` desk line, table marker, statusline label, decision log | `bin/claude-accounts` (`render_readout`/`render_table`/`--json`/`log_assignment`), `statusline.sh` | `claude-accounts-core.bats:394,417`, `statusline-identity.bats` |
| **W3** | S | Launcher robustness + the startup board | `lib/claude-launcher.zsh`, new `hooks/accounts-board.sh`, `migrations/0011-*.sh` | `tests/claude-launcher-router.bats` (15), `deploy-migrations.bats` |

**Serialization:** W1 and W2 both edit `bin/claude-accounts`. **W1 lands first**, W2 rebases onto it.
W0 and W3 are disjoint from both and from each other.

> 🚨 **CORRECTION 2026-08-11 (implementation) — the table above is wrong about W3, and W3 must
> split.** The "Files owned (no overlap)" column gives W3 `lib/claude-launcher.zsh` + the new hook +
> the migration, but **§3 W3 item 6 puts the narrow renderer in `bin/claude-accounts`** ("a new
> renderer mode … NOT a second hand-built table"). That is the same file W1 and W2 own, so W3 as
> written is *not* disjoint and three sessions would have collided in it. Actual execution:
>
> | Wave | Files | Order |
> |---|---|---|
> | **W3a** | `lib/claude-launcher.zsh`, `tests/claude-launcher-router.bats` | concurrent with W1 — genuinely disjoint |
> | **W3b** | `bin/claude-accounts` (`--narrow`), `hooks/accounts-board.sh`, `migrations/0011-*.sh` | **after W2** |
>
> Generalisable: a file-ownership table is only as good as its narrowest claim, and the collision
> was in the *prose* of the item, not the table — the table was never re-derived from the items.

**Lead context budget:** succession point after W0 + W1 land. Do not carry W2/W3 review in the same
context as W1 implementation.

---

## 1. What the operator reported, and what was actually true

| Report | Verdict |
|---|---|
| "routed us to Account3 when /accounts recommends Account1" | **Correct-by-policy, +17.2% margin — but on a lane `/accounts` never displays.** Not a bug. R1 |
| "Account 2 is my preference — earlier weekly expiry and low 5-hour used" | **The operator is right and the shipped code is measurably wrong.** R2 |
| "not responsive for the first 7–12 seconds" | **Real, fleet-wide, one hook, 240× fix known.** Not reso. R4 |
| "print /accounts at startup, zero LLM cost" | **Achievable and now proven at source.** R5 + lead probe |

---

## 2. Findings that drive the work

### 2.1 The routing surprise is a surface mismatch, not a scoring fault (R1, R6)

`render_readout` computes only `ranked(…,"general")` and `ranked(…,"fable")`
(`bin/claude-accounts:2202-2206`); the table `➤` comes from `pick_g` (`:2237-2242`) and the footer
prints exactly two `route_line`s (`:2630`, `:2632`). The launcher routes on `--route interactive`
(`lib/claude-launcher.zsh:59`). **The lane bare `claude` uses is rendered nowhere.**

The lanes can invert completely. Demonstrated numerically with the real `load_cfg()`:

```
two healthy accounts — "far" = weekly 10%, resets in 150h; "soon" = weekly 60%, resets in 3h
general     -> [('soon', 0.064000), ('far', 0.000040)]
interactive -> [('far',  0.847059), ('soon', 0.376471)]
```

`/accounts` would print `➤ general → soon` while bare `claude` launched onto `far`.

At the incident (2026-08-11T20:05:28Z) `score_interactive` ranked **next3 0.6334 ▸ next 0.5402**
(+17.24%), driven by weekly headroom 0.97 vs 0.56. `score_general` ranked next3 **last**. Refuted as
causes: phantom `--assign` feedback (next3's fire was 570 s past the 900 s TTL), cache staleness
(quotas flat for the preceding hour), 5h rollover (none occurred).

### 2.2 The desk objective is wrong, and the operator named the right one (R2)

`score_interactive` exists on the claim that reusing `score_general` would "manufacture the 5-hour
wall" (`:1498-1502`). **False**: `score_general` already multiplies by `_soft` (`:1121-1127`) —
hard `S_CUT`=0.85 exclusion plus a *projected* 5h ramp from 50% — and shares `_excluded`, `KF`, `CF`.
The lanes differ in exactly two terms.

Replay of both scorers over all **324 sweeps** of `~/.claude/logs/account-utilization.jsonl`, scored
on what actually happened in the following 6 h:

| lane | 5h wall (≥85%) within 6h | weekly exhaustion | median weekly headroom of pick |
|---|---|---|---|
| `general` (dispatch) | 3.4% | 0% | 73% |
| `interactive` (shipped) | **4.6%** | 0% | 91% |
| hybrid-i (5h floor + general) | 3.1% | 0% | 73% |
| **hybrid-ii (5h-safe set, then earliest weekly reset)** | **0.6%** | 0% | 73% |

The survival lane is **worse at its own job** — `w_rem` dominance sends it to the roomiest *weekly*
account, not the roomiest *5-hour* one. The lanes disagree on **92% of sweeps** (298/324), so the
landing commit's "both lanes name next4 on today's live fleet" was a one-snapshot artifact; it was
validated on a **synthetic pair** because live data could not discriminate.

Weekly exhaustion: **0/324**, both lanes. Meanwhile ≈**30 percentage-points of weekly quota is
forecast to strand this week** (next2 → ≈87%, next → ≈83%, both BEHIND pace). A 5h wall self-heals
in ≤5 h and has three escapes; stranded weekly quota is unrecoverable.

Provenance: the lane landed `9a843f988`, 2026-08-10 22:56, **agent-authored**, justified by finding
"S8" in an agent research wave — the same day the operator's own M7 `/goal` stated the opposite
objective (`docs/plans/ACCOUNT_ROUTING_V2.md:757`). The operator was never consulted.

**Keep**: the cliff no-yield rule (`ranked()` `:1600-1606`) — it is about *eligibility*, its argument
is airtight (`invalid_grant` has no reset), and it is why the lane deserves to exist.

### 2.3 The pick is unstable, and the launcher destabilises it (R1, R8)

`KF` is quantized in 1/8 steps; breakeven `k* = 2.88`, so next3 won at `k_eff ≤ 2` and lost at ≥3.
It flipped ~3 minutes after the launch — because this research wave's own sessions landed on next3
and drove it to `kmax-concurrency`. Consecutive-decision churn: **20.6% lifetime → 43.4% last 100**.

Three destabilisers:
1. **The launcher charges a phantom against its own pick** (`lib/claude-launcher.zsh:84`), TTL 15 min
   — so a second bare `claude` inside 15 min is nudged *away*. Right for dispatch spread; wrong for a
   human desk.
2. **`working_concurrency` returns `None` past a 2.0 s budget** (`:457-459`) and the whole sweep
   silently falls back to the pane census. Measured swing for next3: `k_eff` 2 → 7. Normal walk is
   0.04–0.07 s over 826 transcripts, so a 2 s trip means the box is pathologically loaded — exactly
   when the count matters most. No diagnostic is emitted.
3. **Exclusions dominate the current pick.** Three consecutive live calls returned `next2`, then
   `next`, with stderr `interactive excluded — next=poll throttled ↻ (cached usage); next3=kmax-concurrency`.
   Poll-throttle *staleness* is knocking accounts out of contention entirely.

**Hysteresis was designed and never shipped** (`docs/plans/START_LATENCY_ROUTER.md:82-83`, build item
`:108`): "keep the incumbent unless beaten by a margin". No such term exists in the code.

### 2.4 The interactive lane is unauditable (R1)

`~/.claude/route/route.jsonl` records only `cc-route` (general/fable). The launcher's sole footprint
is one `--assign` row in a ledger shared with `handoff-fire` and pruned 400→200
(`ASSIGN_PRUNE_LINES`, `:1249`). **Only four launcher-routed launches survive in the entire history.**
This investigation was possible only because the incident was the ledger's last line.

### 2.5 The announcement is printed and then erased (R6)

Measured under a real pty: `[[ -t 2 ]]` holds, `◆ routed → nextN` lands at byte 0–10, then CC emits
`ESC[?1049h` + `ESC[2J` at byte 104, **1.42 s later**. Visible ~1.4 s, then swapped out with shell
scrollback and unrecoverable until exit. Structural loss.

Also refuted: `docs/research/cc-startup-modals-2026-08-04.md:82` concluded `tui:"default"` keeps panes
out of the alternate screen, and all four homes were configured on that basis. On 2.1.220 both
`default` and `fullscreen` emit `ESC[?1049h`; only `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1` /
`CLAUDE_CODE_NO_FLICKER=false` suppress it. **Anything depending on "panes are out of alt-screen"
needs re-verification.**

The statusline *does* already show the account — as a bare unlabelled ordinal `(3)`, which requires
holding `.claude-tertiary → 3 → next3` in your head, and says nothing about *why*.

### 2.6 The 7–12 s is one hook, fleet-wide (R4)

**`hooks/setup-task-symlinks.sh` runs 21–22 s, is killed by its own `timeout: 5`, and discards its
work — every session start, every project, every config dir.** Root cause: `find_active_list()` in
`hooks/lib/task-helpers.sh` forks one `jq` per task-list directory to read a 136 KB index —
**~2,400 forks to select 25 entries**. Single-pass rewrite returns the identical answer in
**0.087 s (240×)**.

The 5 s buys nothing: `find_active_list` is at line ~127 of 162, so the kill lands before `_current`,
`.active-list-id` and `TASKS.md` are written (proven by mtime). It **degrades monotonically** — 2,397
directories backing 496 indexed lists, nothing prunes them.

Blocking proven: a scratch project whose only SessionStart hook is `sleep 25` cost **+22.5 s**;
`sleep 5` cost **+0** (absorbed under the existing floor).

Second in line, and the new floor once #1 is fixed: **`hooks/session-start.sh` spends 2.52 s shelling
out to a second 257 MB `claude` CLI to run `mcp list`**, to emit an advisory string. Its own header
budgets up to **15 s** on the retry path — that is the tail turning 7 s into 12 s.

Ablations: reso everything-on 12.44 s · user settings dropped 6.80 s · project settings dropped
13.72 s (*slower*) · `--safe-mode` 3.45 s · empty /tmp project 9.11 s. **reso's project hooks cost
0.02 s and are already correctly gated**; the `pnpm install` seen at 13:05 was a genuine one-shot cold
`node_modules`. MCP ≈1.6 s, parallel, inside noise.

Both SessionStart blocks use a null matcher ⇒ they fire on `startup`, `resume`, `clear` **and**
`compact`. **Every `/clear` re-pays the full 5–6 s.**

Pre-exec (R3) is ~250 ms from anywhere except the reso primary checkout (~1.9–2.2 s), i.e. ~20–25% of
the complaint — but it carries two unbounded arms that reach the same band:
- `git fetch origin main` in `worktree-pool.sh` `fetch_guarded` has **no timeout** and runs over SSH
  with no `ConnectTimeout`. A 6 s transport stall cost **12,064 ms** (git retries).
- A pool slot behind trunk triggers `pnpm install --frozen-lockfile` first-touch: **11.0–14.0 s**
  across three slots; `--offline` still 11 s ⇒ local store work, not network.

Refuted: the `--route` 240 s lock ladder is **structurally unreachable** from the launcher
(`--max-wait 0` raises before touching the lock — 69–113 ms even with the lock held); cold cache
costs the same as warm (71 vs 75 ms).

### 2.7 The zero-token startup channel — PROVEN AT SOURCE (lead probe, `R5b-…`)

A SessionStart hook emitting all three channels at once, run under a real pty, transcript inspected:

| channel | transcript record | reaches operator terminal | enters model context |
|---|---|---|---|
| **top-level `systemMessage`** | `attachment.type = hook_system_message` | ✅ **YES** — renders *inside* alt-screen at byte 2714 (switch at 67) ⇒ **survives** | ❌ **no** |
| `hookSpecificOutput.systemMessage` | never promoted — only echoed in raw stdout | ❌ ignored entirely | ❌ |
| `additionalContext` | `attachment.type = hook_additional_context` | ❌ | ✅ **yes** |

This corrects R5's write-up, which placed `systemMessage` inside `hookSpecificOutput` (the form that
is **silently ignored**) and asserted from documentation that a pre-exec launcher print survives —
R6 measured that it does not. It also closes R7's open uncertainty (§10: "UNPROVEN — probe it").

Rendered form: `⎿ SessionStart:startup says: <text>`. **Multi-line payloads render in full** — but the
current readout is ~100 cols and the TUI **wraps rows mid-token into unreadable soup**. A startup
board therefore needs a **narrow (≤76 col) variant**, not the chat table.

🚨 **And the naive build recreates the very bug we are fixing:** `claude-accounts --readout` measured
**5.33 s**, over a `timeout: 5`, and was killed in the probe. The board hook MUST be a cache read.

---

## 3. The work

### W0 — Latency (highest leverage; ~5 s off every session start, incl. every `/clear`)

1. **`hooks/lib/task-helpers.sh` `find_active_list()`** — replace the per-directory `jq` fork with a
   single index read + stat of only the mapped dirs. Proven: 21 s → **0.087 s**, identical answer.
   Reference implementation preserved at `/tmp/r4/fix.sh` (re-derive; do not trust a /tmp path).
2. **`hooks/session-start.sh`** — take `claude mcp list` (2.52 s, 15 s worst case) off the critical
   path: cache per config-dir with a TTL, or make it async. Do not simply raise the timeout.
3. **Prune the task store** — 2,397 directories backing 496 indexed lists. Without this the fix
   decays again.
4. **`worktree-pool.sh` `fetch_guarded`** — wrap the fetch: `timeout 3 git fetch origin main || …`.
   The existing `else` branch already handles failure ("using last-known origin/main"), and a
   background `ensure` re-fetches every 2–5 min.
5. **`worktree-pool.sh` `cmd_claim`** — prefer a slot already at `origin/main`; fall back to a stale
   slot only after exhausting current ones. Converts the 11–14 s worst case into slot selection at
   zero correctness cost.

**Verify:** re-run R4's ablation (`--safe-mode` floor ≈3.5 s) and the `sleep 25` blocking control.

#### W0 — OUTCOME (2026-08-11, lead-inline) — items 1-2 DONE, 3-5 FILED

| Item | State | Evidence |
|---|---|---|
| 1 `find_active_list` | **DONE** `8d642bca` | hook **28.699 s → 0.598 s** like-for-like on the real store, byte-identical stdout. Fn alone 21.2 → 0.11 s; legacy no-project branch 13.0 → 0.20 s. `_current` + `.active-list-id` mtime-verify as written by the run (TASKS.md correctly absent — that list has 0 tasks and `generate_tasks_md` removes it at `totalOnDisk == 0`). |
| 2 `claude mcp list` | **DONE** `1d03837c` | **2.030 s → 0.036 s** warm. Stale-while-revalidate, not a bigger timeout. |
| — decayed control | **DONE** `29c82bbf` | Not in the plan; found on the way. See below. |
| 3 task-store prune | **FILED** `f9b5ce0c5d17` | Premise re-measured and largely REFUTED — see below. |
| 4-5 `worktree-pool.sh` | **FILED** `399b9938bef8` | **CROSS-REPO** — the file is in `reso-management-app`, not here. |

**Learnings that outlived the diff:**

- **The rewrite's real risk was ORDER, not speed.** Iterating the index instead of the directory
  glob changes which list wins an mtime tie (jq object order is insertion order). Preserved
  deliberately and pinned by a test that an index-order mutant kills. Differential control over the
  live store: **60 pairs, 37 of them multi-list projects (the discriminating population), 0
  mismatches.**
- **The seven existing tests passed on BOTH implementations**, so they credited the rewrite with
  nothing. Two of the three added are mutation-proven; the third is labelled in-file as NOT
  mutation-proven rather than left to imply coverage it lacks.
- **Item 3's premise died with item 1.** "Without this the fix decays again" was true of the
  fork-per-directory shape. Post-fix the scan is 36 µs/dir, so it needs ~28,000 dirs to cost 1 s
  (currently 2,428, of which 2,363 hold no task json). The remaining action is destructive on live
  operator state, so it is filed, not run.
- **A control keyed on `origin/main` expires when its own subject lands there.** The MCP suite's
  only real control replayed `origin/main`, its fix landed as `37ef2489c`, and it had been red at
  HEAD ever since — reading as a regression in whatever diff ran next. Re-pinned to `54555bed1`
  (`37ef2489c^`) plus an assertion that the replayed file really is pre-fix.
- 🚨 **`claude -p` CANNOT measure this fleet's interactive session start.** `asyncRewake` is honored
  only when the session is interactive or has streaming input; in a one-shot `-p` the ~4 h
  `mailbox-wake-arm.sh` watch is dispatched **synchronously** and prompts. Measured: `--safe-mode`
  3.47/3.68 s vs hooks-on 22.24/22.89 s — a delta that is print-mode-only and reaches no
  interactive session. `asyncRewake: true` verified present in all five `settings.json`.
  **Use per-hook timing against the real store instead.** Post-W0 the synchronous set is
  sub-second: `setup-task-symlinks.sh` 0.598 s (real store), `session-start.sh` 0.036 s warm, and
  the other twelve ≤ 0.11 s each under a fixture.
- **Probe hooks in a fixtured `$HOME`, always.** A timing probe run with a throwaway
  `CLAUDE_PROJECT_DIR` inherited this session's real `CLAUDE_CODE_TASK_LIST_ID`, so the hook
  self-indexed a live task list to `/tmp/w0probe` — live-store pollution, restored by hand. The
  hook was doing its job; the probe was malformed.

### W1 — Routing policy

1. **`score_interactive` → two-key** (`bin/claude-accounts:1492`): among `_excluded`-eligible
   accounts, take those with projected 5h utilisation `< 0.60` **and** weekly headroom `≥ 0.15`;
   among those pick the **earliest weekly reset**. Filters **degrade one at a time**, never empty:
   safe-set → 5h-safe-only → all eligible.
   - Floor at **0.60**: below `S_CUT`=0.85 with margin, above the 61% ceiling three accounts have
     ever observed ⇒ binds on pathology, never on ordinary load.
   - ⚠️ **State honestly in the code comment**: the floor is *untested by this data, not validated by
     it* — the fleet almost never approaches 60%, so its insensitivity is absence of evidence.
2. **Kill switches** per the M7 house pattern: `CC_ROUTE_DESK_5H_FLOOR`, `CC_ROUTE_DESK_W_FLOOR`
   (alongside the existing `CC_CLAUDE_ROUTE=off`).
3. **Keep the cliff no-yield rule verbatim** (`ranked()` `:1600-1606`).
4. **Ship the hysteresis** already specified (`START_LATENCY_ROUTER.md:82-83`): keep the incumbent
   account unless beaten by a margin. Per-account `projects`/`sessions`/`history.jsonl` isolation
   makes flapping a real cost for `--resume`.
5. **Exempt `--src claude-launcher` from the desk lane's own phantom charge**, or give it a shorter
   TTL. One phantom is enough to flip the top two at the current fleet state.
6. **Instrument the `k_work` timeout** — emit a `log_event` on the `None` return and surface it in
   `route-meta`, so "was this pick made on working sessions or on panes?" is answerable. Consider
   raising `budget_s` above 2.0.
7. **Record the reversal in the docstring** (`:1492-1511`) — INTEGRATE, do not overwrite. Mark C4
   measured-false with the 3.4%-vs-4.6% number and the `_soft` reason, so the next reader does not
   re-derive S8 from the same plausible-but-wrong premise.

**Blast radius is one call site**: `grep -rn 'route interactive'` finds exactly
`lib/claude-launcher.zsh:59`; everything else is documentation.

**Tests:** `tests/claude-accounts-core.bats` (69, ~55 s). Router constants derive from the repo
`accounts.json`, so a new constant cannot make the fixture silently disagree.

### W2 — Observability

1. **Re-point the table `➤` to the desk pick** (`:2432`, `:2237-2242`). Its own comment (`:2402-2405`)
   says the marker exists because operator feedback asked "which account do I use" — a *human*
   question, wired to the machine's answer because the desk lane did not exist for another 11 days.
   The general pick is consumed programmatically by `handoff-fire`, which does not read tables.
2. **Add a `desk` route line to both footers**, **FIRST** (before general/fable) — it answers "what
   will bare `claude` do". `route_line`'s `f"{label:<7}"` (`:2609`) is 7 wide: use a ≤7-char label or
   widen all three together (82-col budget, `:2617`). The `why` string must use the desk lane's own
   terms, or the footer contradicts the score.
3. **Emit `score_interactive` + its `route_reasons` in `--json`** (`:3136-3138`).
4. **Add `rank_i` to the cliff-warning loop** (`:2645`), else an interactive-only pick with a dying
   login is warned about nowhere.
5. **Label the statusline account**: `(3)` → `(next3)`. `statusline.sh:243-266` already resolves
   `$CFG` and maps it through a literal `case` — add the name to the same arms, **zero new forks**,
   render unchanged at 60–110 ms. Drop the bare ordinal rather than carrying both.
6. **Log the desk decision** to `route.jsonl` (slot=`interactive`) with kind, score, and runner-up —
   not just an `--assign` row into a pruned shared ledger.

**Tests that pin current output and MUST move in the same commit:**
- `claude-accounts-core.bats:394` — asserts **exactly one** row carries `➤`, that it is the general
  winner, and that both header rows keep equal length. A second mark breaks assertion 1; a wider mark
  breaks alignment.
- `claude-accounts-core.bats:417` — greps `"is the pick"` lines.
- `statusline-identity.bats:418,441` are differential with no glyph literal, so a longer marker
  passes provided two instances differ; layer 1 (tests 1–9) is frozen and cannot go red.
- `commands/accounts.md` documents general/fable only — update, or the asymmetry reappears one layer
  down.

### W3 — Launcher robustness + the startup board

1. **D1 (HIGH) — re-sourcing `~/.zshrc` silently un-installs the router.** `~/.zshrc:451` redefines
   `claude()`; `_cc_install_router` then returns early at `claude-launcher.zsh:97` because
   `_claude_pinned` survives. Measured: `functions claude | grep -c _CC_ROUTED_DIR` → 2 before,
   **0 after** a re-source. Bare `claude` reverts to pinned account 1 **with no notice line** —
   indistinguishable from the router legitimately choosing account 1. The activation script itself
   tells the operator to `source $ZSHRC`.
   **Fix:** guard on whether the *current* `claude` is already the router (marker test), not on
   `_claude_pinned` existing; refresh `_claude_pinned` from the new body at that point.
   **Test gap:** `claude-launcher-router.bats:124` double-sources the *lib* (idempotent) and never
   redefines `claude()` between sources — add that case.
2. **D2 (MED) — `claude1` is a frozen snapshot** of the body at first source, so after any rc edit +
   re-source it runs the *old* launcher while `claude2/3/4` run the new one. Live example:
   `~/.zshrc:496` pins `.claude-220` while the header at `:424` still says `.claude-219`. Same fix
   as D1.
3. **D3 (MED-LOW) — a refused launch is still charged.** `--assign` fires at `:84` *before*
   `_cc_route_check` can refuse the launch (`~/.zshrc:456-457`). Charge after the pinned body commits
   to exec, or emit a compensating record.
4. **D4 (LOW-MED) — the account map is cached for the life of the shell** (`:34`). A removed account
   can still be routed to. Route it through `_cc_lib` like the other libs.
5. **D6 — correct the "byte-identical" claim**: `CC_CLAUDE_ROUTE=off` prints a note, so it is not
   byte-identical on stderr (`:29`, migration `:38`).
6. **The startup board** — new `hooks/accounts-board.sh`, SessionStart, emitting **top-level
   `systemMessage`**:
   - **Cache-only.** Read a pre-rendered file; never call `--readout` inline (5.33 s > timeout).
     Producer = the existing `com.claude.accounts-keepwarm` launchd job, extended to write the
     rendered board. Hook cost must be a `cat` (~0 ms).
   - **Narrow variant** (≤76 cols) — the chat table wraps into soup at TUI width. This is a new
     renderer mode in `bin/claude-accounts` (e.g. `--readout --narrow`), NOT a second hand-built
     table: the single-renderer rule is why `render_readout` exists at all.
   - **Staleness must be visible.** A board that silently prints stale numbers is worse than none;
     carry the existing `*` / `↻ poll throttled` semantics and an age stamp.
   - **Show the desk pick** (W2's lane), since that is what the next bare `claude` will do.
7. **Wiring is C10.** `settings.json` is **five separate real files** (5 distinct inodes, measured);
   the mirror's safe mode refuses to touch a forked real file, so it **never propagates**. Wire via
   `./install.sh --config-dir <dir> --wire-hooks` per dir, then `scripts/settings-drift-assert.sh`.
   Land as `migrations/0011-<slug>.sh`, `migration-class: c10`, with `migration-step` and a
   **non-tautological** `migration-verify` (`deploy-migrations.bats` case 9 rejects `true`/`:`/`exit 0`).
   ⚠️ `.claude-next` (**account 1, the default**) has a **forked real `hooks/` dir** (53 files vs 75)
   — the hook file itself will not appear there via the mirror; it needs its own link/install pass.

---

## 3b. Wave outcomes (2026-08-11)

| Wave | State | Landed | Independently re-verified by the lead on trunk |
|---|---|---|---|
| **W0** | DONE | `222e0f0fe` (4 commits) | hook 28.699 s → 0.598 s; differential 60 pairs / 0 mismatches |
| **W1** | DONE | `da9b186f0` | `claude-accounts-core.bats` **77/77 exit 0** |
| **W3a** | DONE | `34da0847f d5768fad1 26dc3ab94 ab8c07fd0` (+`44ba61199`) | `claude-launcher-router.bats` **21/21 exit 0** (15 pre-existing + 6 new) |
| **W2** | DONE | `a77faa729` | core + statusline-identity **100/100 exit 0** (81 + 19) |
| **W3b** | IN FLIGHT | — | board hook · narrow renderer · migration 0011 |

**Deviations, each with its reason — none is a silent narrowing:**

- **W1:** the `DESK_*` constants are range-validated via a new `ROUTER_OPTIONAL_RANGES` map rather
  than added to `ROUTER_KEYS`. `ROUTER_KEYS` is a REQUIRED list and `~/.claude/accounts.json` is a
  symlink into a checkout that LAGS the code during a land, so a required key would `sys.exit`
  every consumer at once. M7's own constants are absent from it for the same reason.
- **W3a:** D3 is **NARROWED, not closed** — no release verb exists in `claude-accounts`, so the
  charge is deferred behind a settle window (`CC_LAUNCH_ASSIGN_SETTLE_S`, 5 s) and a *slow* refusal
  still charges. Documented in the code.
- **W3a refutes R8 on a detail:** the "byte-identical" overclaim exists ONLY at
  `lib/claude-launcher.zsh:29`. R8's claim that `migrations/0009:38` also carries it is FALSE, so
  nothing in `migrations/` needed to move.

🚨 **REMAINING CONVERGENCE — `statusline.sh` IS A COPY SURFACE.** The `(3)` → `(next3)` change is
**INERT until `./install.sh` runs**, and `deploy-live.sh` deliberately does NOT repair copy classes.
`bin/claude-accounts`, `commands/accounts.md`, `hooks/*` and `lib/*` are per-file symlinks and go
live on the checkout fast-forward. So the close-out sequence is: `deploy-live.sh` (symlink classes)
**AND** `./install.sh` (copy classes) **AND** `install.sh --config-dir <dir> --wire-hooks` × 5 for
the new board hook, then `deploy-parity-assert.sh` — reading 3 as NO VERDICT, never as 0.

### 3c. Convergence state at 2026-08-11T23:20Z — READ THIS BEFORE RE-RUNNING ANYTHING

**What is already LIVE** (symlink classes rode the fast-forward to live HEAD `32355a9b1`):
`hooks/lib/task-helpers.sh`, `hooks/session-start.sh`, `bin/claude-accounts`. Verified by grepping
the LIVE files, and by timing the LIVE hook: **`~/.claude/hooks/setup-task-symlinks.sh` = 1.105 s**
(vs 28.699 s pre-fix) under a loaded box — inside its `timeout: 5`.

**What is NOT live, and exactly why — do not "fix" this by forcing it:**

1. `scripts/deploy-parity-assert.sh` exits **1** (a NAMED failure, *not* 3/NO-VERDICT). The single
   name is `launchd/*.plist  COPYSTALE` — 25 tracked, and the copy differs from the repo.
   **Attribution: NOT this plan's diff.** The launchd change in range came from a sibling,
   `f4d9216c2` (autonomy-sweep `CC_FIRE_CLOUD`). Every other class reads `ok`.
2. The remedy the parity script prints is `./install.sh` — and **`install.sh` REFUSES**, correctly:
   the shared checkout is **12 commits behind `origin/main`**, so installing would "copy pre-trunk
   content into `~/.claude` … while printing success. That is the 2026-08-01 failure this guard
   exists to make impossible."
3. `install.sh`'s printed reconcile is `git -C <checkout> pull --rebase origin main`. 🚨 **DO NOT
   RUN THAT HERE.** It advances the live-layer source *outside* `deploy-live.sh`, whose whole job is
   to fast-forward the checkout ONLY to a commit carrying a GREEN post-land tree. Doing it by hand
   deploys 12 UNVERIFIED commits to the live fleet — bypassing the gate, not satisfying it.
4. `deploy-live.sh` is therefore correctly *waiting*: "no GREEN tree is a DESCENDANT of live HEAD";
   lag 11-12 commits / 0 h, **inside the degrade budget (25 / 6 h)**.
5. The gate is **healthy and mid-run, not stuck** — `~/.claude/autonomy/postland/runner.log` shows
   `com.claude.postland-verify` actively verifying `e5d9ed514` (441 tree suites, 8352 tests planned)
   at the time of writing.

**So the correct action is to WAIT, then run in this order:** `deploy-live.sh` (advances the
checkout once a green tree descends live HEAD) → `./install.sh` (copy classes: `statusline.sh`,
the plists) → `deploy-parity-assert.sh`. ⚠️ Once W3b lands, `hooks/accounts-board.sh` and
`migrations/0011-*` are **ADDs**, and an ADD gets NO converge budget — absent, not stale, with every
`[ -f x ]` consumer guard silently skipping — so that land breaches at a lag of 1 and needs
`install.sh --config-dir <dir> --wire-hooks` for all five dirs, including the forked `.claude-next`.

**Process finding worth more than the diff:** `handoff-fire.sh`'s INC-4 engagement detector gave a
FALSE NEGATIVE twice (panes 379, 384 — both declared "never engaged … TASK-LESS", both then did
their whole wave correctly). Its printed recovery is a warm re-fire into the SAME worktree, which
put two sessions on `bin/claude-accounts` for W1; only the sibling's own duplicate-detection (pane
381 stood down without writing a byte) prevented a clobber. **The prescribed remedy is more
damaging than the symptom.** Filed `87626e1593c3`.

---

## 4. Open decisions for the operator

**D-A. Should `accounts[0].launcher` flip `claude` → `claude1`?** Migration `0009-start-latency-router`
says the two surfaces must move together, because `handoff-fire.sh:6070` resolves
`accounts[N].launcher` and **types it into a pane**. It is currently `claude` (byte-identical to
`origin/main` and to its own pre-router backup), so the flip never happened. It does not mis-route
today only because `handoff-fire` sets `CC_ACCOUNT_PINNED`. This is C10 — the operator's call.

**D-B. Should the desk be sticky?** Hysteresis (§W1.4) plus phantom exemption (§W1.5) make two
consecutive `claude` invocations land on the same account. That is what a human expects and what
`--resume` isolation rewards — but it *reduces* spread. Recommended: yes, with a margin.

**D-C. `claude-desk` now routes** (`desk.zsh:67` calls bare `claude`), and `desk-register` claims the
role file *before* the launch, so the role is written without knowing which account wins. If any
consumer assumes the desk lives on account 1, that is now false. Needs an intent ruling, not a fix.

---

## 5. Landing (R7)

- Repo `/Users/chrisren/Development/claude-infrastructure`, trunk `origin/main`.
- **Landing is FREE and standing-authorized** — `.claude/CLAUDE.md` § "Standing-land authorization
  (this repo only)". Use the **project-local** `/ship` (`.claude/commands/ship.md`), never the global
  one, never a bare `git push`.
- **Never commit in the shared checkout** (incident 2026-07-11: a 5-file commit was silently
  rebase-dropped by a sibling `/ship` while `rev-list` read 0). Work in `desk-router`.
- **LANDED ≠ LIVE.** `~/.claude/**` is per-file symlinks, so a **new file** (the board hook, the
  migration) is not linked until `install.sh` runs. Converge with
  `scripts/deploy-live.sh`, then `scripts/deploy-parity-assert.sh` (0 parity · 1 named · **3 = NO
  VERDICT**, never conflate with 0). `statusline.sh` and `CLAUDE.md` are **COPY** surfaces — even an
  *edit* is inert until `install.sh` runs.
- `bats` is `cc-bats` and **defers under load**: a deferral is loud on stderr and never exit 0. Never
  pipe (`cmd | tail` returns tail's status). Use `CC_BATS_MAX_ROOTS=0` to override.
- Use migration number **0011** (`0010` is highest; two `0009`s already coexist and nothing enforces
  uniqueness).

---

## 6. Definition of done

- [ ] Session start: measured floor back to ≈3.5 s; `setup-task-symlinks.sh` completes under its
      timeout and writes `_current`/`.active-list-id`/`TASKS.md` (mtime-verified).
- [ ] `claude-accounts --route interactive` implements the two-key rule; 69 core tests green.
- [ ] `/accounts` shows a **desk** line first, and the table `➤` marks the desk pick.
- [ ] Statusline reads `(next3)` not `(3)`.
- [ ] Re-sourcing `~/.zshrc` leaves the router installed (new test case green).
- [ ] SessionStart board renders the narrow table at ~0 ms hook cost and **0 model tokens** —
      verified by inspecting the transcript for `hook_system_message` and the **absence** of the
      board text in any `hook_additional_context` record.
- [ ] Landed via project-local `/ship`; `deploy-parity-assert.sh` exit 0; `deploy-migrations.sh
      --status` shows `0011` staged with a real verify.

---

## 7. Provenance

R1 route replay · R2 policy design · R3 pre-exec latency · R4 post-exec latency · R5 startup-print
(**superseded in part** by the lead probe — see §2.7) · R6 observability · R7 landing ground map ·
R8 entrypoint audit. All in `docs/research/` beside this file, with the render probe as
`R5b-sessionstart-render-probe.py`.
