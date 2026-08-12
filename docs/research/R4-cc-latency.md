# R4 — Claude Code post-exec startup latency: measured attribution

Binary `2.1.220` (`~/.claude-220/node_modules/.bin/claude`, Mach-O arm64, 257 MB).
Config dir `~/.claude-tertiary`. cwd `/Users/chrisren/Development/.worktrees/wt-pool-1`.
Measured 2026-08-11 on this box under normal fleet load. Every number carries its command.
Scope: everything AFTER `exec`; the zsh chain is R3's.

Hook paths below are written as `hooks/<name>` — they resolve to
`~/Development/claude-infrastructure/hooks/<name>`, symlinked into the user config dir.

---

## VERDICT — one hook accounts for the whole stall, and it is FLEET-WIDE, not reso

**`hooks/setup-task-symlinks.sh` runs for 21-22 s, is killed by its own `timeout: 5` in the
user-scope settings, and burns those 5 s blocking EVERY session start — in every project, on
every config dir.** Its work is discarded. Fix it and `hooks/session-start.sh` (which shells
out to a *second whole `claude` CLI* to run `mcp list`, 2.52 s) becomes the new floor.

The lead's prime suspect — reso's `pnpm install` SessionStart hook — is **REFUTED for the
steady state**. It is gated `if [ ! -d node_modules ]`, node_modules is present, and all six
reso project hooks measure **0.00-0.02 s** combined. It fired once today (13:05) because this
worktree's node_modules was genuinely absent — one-shot provisioning, not the complaint.

**The 7-12 s is not reso-specific.** An empty `/tmp` project with the same user settings
reproduces the identical profile (settle points 5.75 s / 9.05 s vs reso's 5.85 s / 9.26 s);
the same reso worktree with user settings dropped finishes rendering at **1.30 s** with no
later settle at all.

---

## 1. Ordered per-stage table

Timeline from one instrumented run
(`claude -p 'ok' --model claude-haiku-4-5-20251001 --debug-file /tmp/r4/dbg.log -d hooks`),
t=0 at the first debug line `20:31:16.903`, API dispatch at `20:31:22.637`.

| # | Stage | median ms | blocking? | scope | source |
|---|---|---|---|---|---|
| 1 | node/bundle boot (`--version`) | **70** | yes | binary | `time claude --version` x3 -> 0.07/0.07/0.07 |
| 2 | full CLI parse (`--help`) | **160** | yes | binary | `time claude --help` x3 -> 0.16/0.20/0.16 |
| 3 | settings + MDM + permission-rule load | **~300** | yes | user+project | dbg 16.903->17.121; `Adding 492 allow rule(s) to destination 'localSettings'` |
| 4 | skills/commands/agents/plugins load | **159** | yes | user+project | dbg `[STARTUP] Commands and agents loaded in 159ms`; 93 skills |
| 5 | MCP configs resolve | **207** | yes | user+project | dbg `[STARTUP] MCP configs resolved in 207ms (awaited at +224ms)` |
| 6 | MCP HTTP connects (motion / motion-plus / uidotsh) | **191 / 385 / 386** | **no** (parallel) | user `.claude.json` + project `.mcp.json` | dbg `Successfully connected (transport: http) in NNNms` |
| 7 | claude.ai MCP registry fetch | **~640** | no (parallel) | user | dbg 17.170 -> 17.808 |
| 8 | **SessionStart hooks, user scope — see section 2** | **~5 000** | **YES** | **fleet-wide** | section 2 + ablation section 3 |
| 9 | SessionStart hooks, reso project scope | **~20** | yes | project | section 2b |
| 10 | first-request assembly (93-skill attachment, 27 deferred tools) | **~200** | yes | user+project | dbg 22.440 -> 22.637 |
| 11 | **=> time to first API dispatch** | **5 734** | — | — | dbg 16.903 -> 22.637 |
| 12 | API first byte (haiku, trivial prompt) | 1 623 | — | — | dbg `[API:timing] first byte after 1623ms` |
| 13 | statusline command (per render) | **45** | no | fleet | `statusline.sh` x5 -> 0.07/0.04/0.04/0.05/0.04 |

TUI-side (pty capture via `script -q /dev/null claude ...`, output-byte trace sampled 100 ms;
harnesses `/tmp/r4/tui3.sh`, `/tmp/r4/tui4.sh`, both preserved):

| Event | reso (full) | reso, user settings dropped | empty /tmp project (full) |
|---|---|---|---|
| input box painted | 1.36 s | 1.18 s | 1.07 s |
| last render | — | **1.30 s (done)** | — |
| settle #1 | **5.85 s** | *(never)* | **5.75 s** |
| settle #2 | **9.26 s** | *(never)* | **9.05 s** |

The frame *paints* at ~1.4 s. What the operator experiences as "unresponsive" is the
5.8 s / 9.1 s window where the box is up, the session has not settled, and (section 3) a
submitted turn cannot start.

---

## 2. Per-hook measurement

Real SessionStart JSON on stdin, `source: "startup"`, run under
`env -u CC_PANE_ID -u ITERM_SESSION_ID -u CLAUDE_CODE_TASK_LIST_ID`, cwd = reso worktree.
Harness `/tmp/r4/th.sh`. 3 runs each, seconds.

### 2a. User scope (fleet-wide — this settings file is mirrored across ~12 config dirs)

| Hook | runs (s) | declared `timeout` | effective blocking cost |
|---|---|---|---|
| **`hooks/setup-task-symlinks.sh`** | **22.51 / 21.90 / 21.64** | **5** | **5.00 s — killed, work discarded** |
| `hooks/session-start.sh` | 2.65 / 2.52 / 2.47 | 10 | 2.52 s |
| `hooks/activation-watch.sh` | 0.63 / 0.62 / 0.63 | 5 | 0.63 s |
| `hooks/setup-plan-symlinks.sh` | 0.31 / 0.32 / 0.35 | 5 | 0.32 s |
| `hooks/pre-session-validate.sh` | 0.10 x3 | 10 | 0.10 s |
| `hooks/session-index-start.sh` | 0.08 x3 | — | 0.08 s |
| `hooks/dod-persist.sh` | 0.07 x3 | 5 | 0.07 s |
| `hooks/live-session-registry.sh` | 0.07 x3 | — | 0.07 s |
| `hooks/config-mirror-assert.sh` | 0.06 x3 | — | 0.06 s |
| `hooks/session-register.sh` | 0.05 x3 | 5 | 0.05 s |
| `hooks/lead-crash-watchdog.sh` | 0.04 x3 | 10 | 0.04 s |
| `hooks/frontier-status.sh` | 0.03 / 0.02 / 0.03 | — | 0.03 s |
| `hooks/mailbox-drain.sh session-start` | 0.02 x3 | — | 0.02 s |
| `hooks/mailbox-wake-arm.sh` | 0.02 x3 | 14400 + `asyncRewake` | 0.02 s (async) |
| `hooks/desk-brief-inject.sh` | 0.01 x3 | 5 | 0.01 s |

Hooks run **concurrently**, so the group cost is the **max**, not the sum: ~5.0 s, set
entirely by the capped `setup-task-symlinks.sh`. Corroborated three ways:
(a) sum = 8.6 s but the measured group cost is 5.6 s (section 3);
(b) the debug timeline shows `session-start.sh` returning at t=3.42 s and the next event at
t=5.54 s, i.e. hook-start + 5.00 s exactly;
(c) `session-index-start.sh` (a later hook group) completes at t=1.03 s, so groups overlap.

### 2b. Project scope (reso project settings, SessionStart block)

| Hook | runs (s) | note |
|---|---|---|
| `if [ ! -d node_modules ]; then ... pnpm install; fi` | 0.00 x3 | **gate false** — node_modules present (mtime Aug 11 13:06) |
| `.env.local` copy from main worktree | 0.01 x3 | `.env.local` present (Aug 11 02:21) |
| `if [ ! -f sqlite.db ]` DB provision | 0.00 x3 | `sqlite.db` present (Aug 11 13:00) |
| `touch ~/.reso/worktree-gc.wake` | 0.00 x3 | |
| unblock-sweep 20 h gate | 0.00 x3 | last run 13:13 today; when it fires it spawns `tsx` — **tsx boot alone measures 0.85/0.77/0.77 s** |
| project `hooks/mcp-auth-guard.sh` | 0.02 x3 | |

**Total reso project SessionStart cost ~0.02 s warm.** Note the reso `timeout` values are in
milliseconds where Claude Code's hook `timeout` field is **seconds** (`120000`, `5000`,
`20000`, `30000`) — i.e. 33 h / 83 min / effectively unbounded. Harmless today because the
gates are false, but a cold `pnpm install` there has no ceiling.

---

## 3. Blocking proof and scope ablation

### Do SessionStart hooks block? YES — measured, not inferred.

Scratch projects whose only SessionStart hook is `sleep N`:

| project hook | runs (s) | median | delta vs no-hook |
|---|---|---|---|
| none (`/tmp/cc-probe-nohook`) | 9.89 / 11.46 / 11.28 | 11.28 | — |
| `sleep 5` | 9.91 / 10.62 / 12.24 | 10.62 | **+0** (absorbed under the existing ~5 s floor) |
| `sleep 25` | 33.87 / 33.73 | 33.80 | **+22.5 s** |

`sleep 5` costing nothing while `sleep 25` costs 22.5 s is itself the proof that the harness
waits for the *slowest* SessionStart hook and that the pre-existing floor is ~5 s.

### Where does the cost live? (`claude -p 'ok' --model claude-haiku-4-5-20251001`, 3 runs)

| configuration | runs (s) | median |
|---|---|---|
| reso, everything on | 10.79 / 12.44 / 12.60 | **12.44** |
| reso, **user settings dropped** (`--setting-sources project,local`) | 5.92 / 6.80 / 7.89 | **6.80** |
| reso, project settings dropped (`--setting-sources user`) | 13.72 / 11.55 / 14.74 | 13.72 |
| reso, MCP off (`--strict-mcp-config --mcp-config '{"mcpServers":{}}'`) | 10.29 / 16.43 / 10.80 | 10.80 |
| reso, `--safe-mode` (all customisation off) | 3.30 / 4.01 / 3.45 | **3.45** |
| empty /tmp project, everything on | 9.11 / 8.77 / 11.65 | 9.11 |
| empty /tmp project, `--safe-mode` | 3.57 / 2.94 / 5.11 | 3.57 |

- user-scope settings cost **12.44 - 6.80 = 5.6 s** — matches the 5 s cap plus scheduling.
- project (reso) settings cost **<= 0** (13.72 >= 12.44). reso adds nothing.
- MCP costs **~1.6 s at most**, largely parallel. Not the bottleneck.
- floor with everything off is **~3.5 s**, of which 1.6 s is the API round trip.

---

## 4. Root cause of the 21 s

`hooks/lib/task-helpers.sh` -> `find_active_list()` loops over **every** task-list directory
and forks a `jq` per directory to read that list's project mapping out of a 136 KB index:

```
for dir in "$TASKS_DIR"/*/; do
    mapped=$(jq -r --arg k "$listid" '.taskLists[$k].project // ""' "$index")   # one fork per dir
```

Scale on this box: **2 397 task directories** (`ls ~/.claude-tertiary/tasks | wc -l`); index
`tasks-index.json` is 136 128 B with 496 entries, of which **25** map to this project. So it
forks ~2 400 `jq` processes, each re-parsing 136 KB, to select 25.

Isolated (`/tmp/r4/fa.sh`): `find_active_list` alone = **21 s** — i.e. the whole hook. The
`_summary.json` staleness loop above it (already optimised, per its own header comment) is ~1 s.

**The corrected form is 240x faster and returns the identical answer.** Read the index once,
stat only the mapped dirs (`/tmp/r4/fix.sh`):

```
single-pass find_active_list -> wt-pool-1-cc-102104-36528 in 0.087s
single-pass find_active_list -> wt-pool-1-cc-102104-36528 in 0.088s
single-pass find_active_list -> wt-pool-1-cc-102104-36528 in 0.088s
```

versus the shipped loop's `wt-pool-1-cc-102104-36528 in 21s`.

**The 5 s is pure waste, not a slow-but-useful step.** `find_active_list` is called at line
~127 of 162; the kill lands before `_current`, `.active-list-id` and `TASKS.md` are written.
Evidence: after this session's 13:05 start the per-list symlinks carry mtime 13:05 (they are
written earlier in the script) while `_current` / `.active-list-id` / `TASKS.md` kept an older
mtime until **my own uncapped probe** rewrote them at 13:36. The hook's header already records
this failure mode verbatim: *"killed by this hook's own settings timeout:5 with the work
discarded every time — the fleet's single largest hook."* That prior fix addressed the
`_summary.json` loop only; `find_active_list` was left on the O(all-dirs) x fork path.

**It degrades monotonically.** Directories accrue per session (3 434 sessions in the index
log) and nothing prunes 2 397 dirs. The hook will sit pinned at its 5 s cap forever.

---

## 5. Removable / cacheable / backgroundable / inherent

| Cost | median | disposition |
|---|---|---|
| **`setup-task-symlinks.sh` 5 s cap** | 5 000 ms | **REMOVABLE — the fix measures 0.09 s.** Replace the per-dir `jq` fork in `find_active_list` with one index read (proven above). Also prune the task store: 2 397 dirs backing 496 indexed lists. |
| **`session-start.sh` `claude mcp list`** | 2 520 ms | **REMOVABLE or BACKGROUNDABLE.** It spawns a second 257 MB CLI to answer a question the running session already knows, purely to emit an advisory `additionalContext` string. Options: cache per config-dir with a TTL; move off the critical path (the framework supports async — `mailbox-wake-arm` uses `asyncRewake`); or drop it. Its own header prices one probe at 2.51-2.89 s and budgets up to **15 s** on the retry path — that is the tail that turns 7 s into 12 s. |
| MCP HTTP connects (4 servers) | 191-386 ms each | **INHERENT, already parallel, not blocking.** Disabling MCP saved ~1.6 s median, inside run-to-run noise. Leave alone. |
| settings / permission-rule parse | ~300 ms | **Trimmable.** 492 allow rules in local settings + 19 project deny + ~200 user rules. Recovers <=150 ms. Low priority. |
| 93-skill attachment (46 716 chars vs 8 000 budget) | ~200 ms wall | Real cost is tokens, not latency. Binary warns `Skill listing over budget ... descriptions will be truncated`. Separate problem. |
| statusline | 45 ms | inherent, negligible |
| binary boot | 70-160 ms | inherent |
| API first byte | 1 623 ms | inherent |
| reso `pnpm install` hook | 0 ms warm | **already conditional and correct.** `scripts/prepare-cached.sh` additionally sha-caches `styled-system/` + `preview-atoms.css` on a clean tree (~5 s -> ~0.3 s), falling back to the full chain on any doubt. Nothing to fix. The 15.7 s install the lead saw was a genuine cold node_modules at 13:05, one-shot. |
| reso unblock-sweep (every 20 h) | 0 ms usually | when it fires: >=0.8 s tsx boot plus the sweep. Background it. |

**Ranked contribution to the operator's stall:**
1. `setup-task-symlinks.sh` — 5.0 s, 100 % of the blocking floor (everything else hides under it).
2. `session-start.sh`'s `claude mcp list` — 2.5 s; becomes the floor the moment #1 is fixed, 15 s worst case.
3. Everything else combined — ~1.0 s.
4. reso project hooks — 0.02 s. Not a factor.

---

## 6. Direct answers to the brief

- **Which hook ran `pnpm install`?** The first SessionStart entry in reso's project settings.
  It is **conditional** (`[ ! -d node_modules ]`), **blocking**, fires on **all** sources
  (`matcher: ""`), and is **project-specific**. Its gate was true only because this worktree's
  node_modules was absent at 13:05 (mtime proves the rebuild). It is a no-op now.
- **Is it already conditional / does something already cache it?** Yes, twice: the
  `[ ! -d node_modules ]` gate, and `scripts/prepare-cached.sh` for the `prepare` codegen.
- **Do SessionStart hooks block?** **Yes, proven** (`sleep 25` -> +22.5 s end-to-end).
- **Every start or only some sources?** Every one. Both the user and project SessionStart
  entries use `matcher: null` / `""`, which matches `startup`, `resume`, `clear` and `compact`
  — so **`/clear` re-pays the full 5-6 s**.
- **Is `DISABLE_AUTOUPDATER=1` honoured?** Yes. No update check in the debug log; `--version`
  returns in 70 ms.
- **Network / Keychain on the startup path?** Network yes, all parallel and non-blocking:
  4 MCP connects (191-386 ms), `api.anthropic.com/v1/mcp_servers` (~640 ms), a bootstrap
  fetch. No Keychain read appears in the debug log.
- **reso-specific or universal?** **Universal.** An empty /tmp project reproduces the settle
  points at 5.75 s / 9.05 s; reso with user settings dropped renders fully at 1.30 s.

---

## 7. Adversarial pass — the holes a hostile reviewer would go for

1. *"You only measured `-p`; the complaint is the TUI."* -> Ran the TUI in a pty and traced
   output bytes. The stall reproduces there (5.85 s / 9.26 s), vanishes when user settings are
   dropped (1.30 s), and reproduces in an empty project. Section 1.
2. *"Maybe MCP is the real cost and hooks are noise."* -> `--strict-mcp-config` ablation:
   10.80 s vs 12.44 s, inside noise; connects are 191-386 ms and concurrent. Refuted.
3. *"Maybe it's reso's huge local settings / CLAUDE.md."* -> `--setting-sources user` (drops
   reso entirely) measured **13.72 s**, *slower* than full. Refuted.
4. *"Your 21 s is a loaded-box artefact."* -> 3 consecutive runs at 21.64-22.51 s, and the
   mechanism is structural (~2 400 forks). Even a 4x faster box exceeds the 5 s cap.
5. *"Maybe the hook's work is fine, just slow."* -> Checked the artefacts it should write.
   `_current` / `.active-list-id` / `TASKS.md` are written *after* the kill point; the per-list
   symlinks (written before it) carry the session-start mtime, those three did not. The 5 s
   buys nothing.
6. *"Did you break anything?"* -> Read-only w.r.t. tracked files and the config dirs; scratch
   confined to `/tmp/r4`, `/tmp/cc-probe-*`, `/tmp/cc-cfg-*`. One disclosure: my uncapped probe
   of `setup-task-symlinks.sh` at 13:36 refreshed this worktree's `.claude-tasks/_current` and
   `TASKS.md` to `wt-pool-1-cc-102104-36528` — the same value the hook would have produced. A
   correction, not damage, but it is a write and it is named here.

## 8. UNKNOWN / unmeasured

- Whether the TUI **swallows** keystrokes typed before hooks complete or queues them. The box
  paints at 1.4 s and the first turn provably cannot start before hooks finish; the keystroke
  behaviour itself was not probed (needs a real interactive submit).
- Attribution of the second TUI settle at 9.05-9.26 s (+59 bytes). It is caused by user-scope
  settings (absent under `--setting-sources project,local`), but that lever also drops
  `statusLine`, so statusline-first-render and hook-tail cannot be separated by it.
- Cost of the reso unblock-sweep when it actually fires (only its >=0.77 s `tsx` boot was
  measured; the sweep body has side effects and was not run).

## 9. Incidental findings (not latency)

- TUI warns: `/Users/chrisren/.claude-tertiary/CLAUDE.md is over the 40.0k-char limit (62.0k chars)`.
- Binary warns: `Skill listing over budget: 93 skills, 46716 chars > 8000 budget`.
- reso project hook `timeout` values use milliseconds where the field is seconds.

---

## R6 — implemented 2026-08-12: SessionStart group max 0.9s → 0.24s

§5's top two were already landed by the desk-router session (`find_active_list` single-pass
`d31fee77f`, 21s → 0.09s; session-start mcp SWR `1d03837c`, 2.03s → 0.036s). This pass took
the residual floor. Group cost = max of concurrent hooks; every rewrite A/B'd byte-identical
on the live stores before landing (infra `a09ce88e3`):

| Hook | before | after | how |
|---|---|---|---|
| activation-watch.sh | 660–900ms | **126ms** | fork collapse: ONE batched stat for the queue (was one per file), ONE `LC_ALL=C diff -rq` yielding parity's three classes (was a cmp fork per script plus two globs), ONE `grep -H` + builtin `case` scans for inert (was grep+awk per candidate). Selftest 26/26, /Users/chrisren/.claude/bin/cc-bats 38/38, output byte-identical on the live queue. |
| setup-task-symlinks.sh | 800ms | **237ms** blocking | index prune + the 2,479-dir summary sweep + a NEW empty-dir GC (`rmdir`, >7d — the store grows one dir per session, 97% empty, nothing pruned it) moved to a detached, stamp-throttled `--sweep` self-reentry; the ACTIVE list's summary still regenerates synchronously (TASKS.md needs it; guard factored to task-helpers `summary_stale`). /Users/chrisren/.claude/bin/cc-bats 8/8. |
| setup-plan-symlinks.sh | 560ms | **69ms** | ONE awk pass over every plan's frontmatter (was `plan_status` × 254 files × ~3 forks each). Same status grammar; unknown stays OPEN (anti-FM1). |
| **group max** | **~900ms** | **~240ms** | paid at every session start, every project, every config dir, including every `/clear` |

With §1, time-to-usable is now bounded by the binary's own ~1.1–1.4s to paint plus ~0.24s of
hooks — everything this fleet's own code contributes to the startup path is sub-second. The
remaining floor is CC-internal (settings ~300ms, skills/commands 159ms, MCP configs 207ms,
API first byte) plus R3's pre-exec ~0.6s from the reso primary.
