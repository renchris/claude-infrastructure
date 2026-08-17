# Layer measurement: SessionStart hooks (15) — 2026-08-16

Axis: `sessionstart-hooks`. Box: operator's macOS, ~24 live Claude sessions concurrent.
All measurements RE-DERIVED today; prior art treated as claims.

## 0. Config as read today (READ-ONLY)

`~/.claude/settings.json` → `hooks.SessionStart` is an array of **6 matcher groups**:

- group 1 (10 hooks): session-start.sh(10), setup-plan-symlinks.sh(5), setup-task-symlinks.sh(5),
  pre-session-validate.sh(10), lead-crash-watchdog.sh(10), session-register.sh(5),
  activation-watch.sh(5), dod-persist.sh(5), desk-brief-inject.sh(5),
  mailbox-wake-arm.sh(**14400**, `asyncRewake:true`)
- group 2: session-index-start.sh (5)
- group 3: config-mirror-assert.sh (8)
- group 4: frontier-status.sh (5)
- group 5: live-session-registry.sh (5)
- group 6: mailbox-drain.sh session-start (5)

(timeout in seconds, per CC hook schema)

Command:
```
cd /Users/chrisren/.claude && python3 -c "import json;d=json.load(open('settings.json'));print(json.dumps(d['hooks']['SessionStart'],indent=1))"
```

## 1. Prior art read

- `R4-cc-latency.md` (2026-08-11, binary 2.1.220, cfg `.claude-tertiary`) — claims:
  - SessionStart hooks BLOCK the first API dispatch (proved with `sleep 25` → +22.5s).
  - Hooks run CONCURRENTLY; group cost = max, not sum.
  - `setup-task-symlinks.sh` was 21s (killed at its 5s cap) — the whole floor.
  - `session-start.sh` shelled out to a second `claude mcp list` = 2.52s.
  - § R6 (added 2026-08-12): both fixed. Group max **900ms → ~240ms**
    (activation-watch 660–900→126ms; setup-task-symlinks 800→237ms; setup-plan-symlinks 560→69ms).
- `R5-startup-print.md` — about output channels (systemMessage vs additionalContext), not latency.

So the prior art's own final state is: **this layer already got its speed-up on 2026-08-12** and
should now cost ~240ms. That is the claim under test today.


---

# PART A — SEMANTICS, RE-DERIVED TODAY (2026-08-16), binary 2.1.220

## A0. Which binary actually runs (correction to the lead's ground truth)

`~/.claude-versions/current` → `2.1.114`, but **no live session runs it**. All 36 live
`claude` processes on the box run `~/.claude-220/node_modules/.bin/claude` (2.1.220),
launched under `~/.claude/bin/cc-close-attrib`.

```
ps -axo command= | grep -oE "/Users/chrisren/[^ ]*claude[^ ]*/node_modules/\.bin/claude" | sort | uniq -c
#   36 /Users/chrisren/.claude-220/node_modules/.bin/claude
/Users/chrisren/.claude-versions/current/node_modules/.bin/claude --version  # → 2.1.114
```

So every measurement below uses **`~/.claude-220/.../claude` (2.1.220)** — the binary the
fleet actually runs, and the same one R4 measured.

## A1. Probe harness (ZERO API TOKENS SPENT — no `claude -p` was ever run)

Throwaway config dir `/tmp/ssprobe/cfg`, throwaway project `/tmp/ssprobe/proj`.
Two seeding steps were required before hooks would fire at all (each is itself a finding):

1. a bare `CLAUDE_CONFIG_DIR` lands in the **theme-picker onboarding** → hooks never run.
   Fixed by seeding `<cfg>/.claude.json` with `hasCompletedOnboarding:true` + `theme`.
2. a `/tmp` project then hits the **folder-trust prompt** → hooks still never run.
   Fixed by seeding `projects["/private/tmp/ssprobe/proj"].hasTrustDialogAccepted = true`.

Harness: `/tmp/ssprobe/ptyprobe2.py` — `pty.fork()` + `execvp` of the real binary, byte-level
output timestamps, optional keystroke injection, then SIGINT+SIGKILL of *its own* child.
Hook under test: `/tmp/ssprobe/h.sh <name> <sleep>` which appends
`NAME START <epoch.6>` / `NAME END <epoch.6>` to `/tmp/ssprobe/log/t.log`.

## A2. (a) SERIAL or PARALLEL? → **PARALLEL, and across matcher groups too**

Config: 4 sleep-3 hooks, three in matcher-group 1 and one in matcher-group 2.

```
cd /tmp/ssprobe/proj && PROBE_DUR=16 CLAUDE_CONFIG_DIR=/tmp/ssprobe/cfg \
  python3 /tmp/ssprobe/ptyprobe.py /Users/chrisren/.claude-220/node_modules/.bin/claude
```

```
A START 1786919045.989443
B START 1786919045.989690
D START 1786919045.989691      ← different matcher group
C START 1786919045.989886
D END   1786919049.020806
B END   1786919049.020957
C END   1786919049.024713
A END   1786919049.024732
```

All four STARTs span **0.44 ms**. Wall clock for four 3 s hooks = **3.03 s**, not 12 s.
⇒ **group cost = MAX, not sum.** Matcher groups do NOT serialise relative to each other.
This confirms R4's claim and extends it (R4 inferred cross-group overlap indirectly; here
it is a direct timestamp).

## A3. (b) Do they block FIRST PAINT or the FIRST PROMPT? → **not paint; yes prompt**

Same 4 hooks, sleep 0 vs sleep 6, with `/help` (a purely LOCAL slash command — no API call,
so this test costs zero tokens) typed into the pty at t=1.2 s.

| | sleep=0 | sleep=6 |
|---|---|---|
| first byte | 0.311 s | 0.379 s |
| **full frame painted** (banner + input box + status line) | **~0.46 s** | **~0.51 s** |
| hooks start | 0.357 s | 0.437 s |
| `/help` typed | 1.361 s | 1.368 s |
| keystroke echoed | 1.374 s | 1.375 s |
| **`/help` output rendered** | **1.374 s** | **6.502 s** |
| hooks would end at | 0.36 s | 6.44 s |

Commands:
```
PROBE_DUR=16 PROBE_TYPE="/help" PROBE_TYPE_AT=1.2 PROBE_OUT=/tmp/ssprobe/o_0.bin \
  CLAUDE_CONFIG_DIR=/tmp/ssprobe/cfg python3 /tmp/ssprobe/ptyprobe2.py \
  /Users/chrisren/.claude-220/node_modules/.bin/claude       # and again with sleep=6
```
Rendered `/help` payload is byte-equivalent in both runs (`o_0.bin`, `o_6.bin`).

**Semantics, stated precisely:**
- The TUI **paints at ~0.5 s regardless** — hooks do not gate the frame.
- Keystrokes **echo** immediately — the box looks alive.
- **Nothing submitted is processed until the slowest SessionStart hook returns** — not even a
  local slash command that never touches the network. `/help` slipped 1.374 s → 6.502 s,
  i.e. **exactly hook-completion + ~60 ms**.

⇒ SessionStart hooks are **BLOCKING on time-to-usable**, and the blocking is *invisible* —
the UI is painted and echoing, so the operator experiences it as "typed and nothing happened",
which is worse than a visible spinner. This is a sharper statement than R4's (which proved
blocking of the first *API dispatch*); it blocks the local command pipeline too.

## A4. (c) `asyncRewake: true` — does it exempt a hook? → **YES, fully**

Config: `FAST` (sleep 0) + `ASYNC` (sleep 6, `timeout:14400`, `asyncRewake:true`).

```
ASYNC START 1786919238.467587
FAST  START 1786919238.467609
FAST  END   1786919238.497874
ASYNC END   1786919244.500662     ← 6.03 s later
```
`/help` typed at 1.384 s, **rendered at 1.399 s** — unaffected. Frame painted 0.49 s.

⇒ **an `asyncRewake` hook is dispatched in the background and costs the critical path 0 ms**,
however long it runs. `mailbox-wake-arm.sh` with `timeout:14400` therefore contributes
**zero blocking milliseconds**. Read of the script confirms the design end-to-end
(`~/.claude/hooks/mailbox-wake-arm.sh` → `hooks/mailbox-wake-arm.sh` in claude-infrastructure):
it consumes stdin, walks ≤6 `ps` ancestors to detect print mode, and in a **one-shot
`claude -p`** exits 0 immediately — because there `asyncRewake` is dispatched SYNCHRONOUSLY
(the binary's gate is `(async || asyncRewake && K) && !d`, `K = !isInteractive || hasStreamingInput`),
which would otherwise wedge a headless session for ~4 h. In an interactive session it runs
`cc-await-ping <key> --timeout 14340` in the background for up to 3 h 59 m and exits 2 on mail.

**It self-backgrounds by harness contract, not by `&`.** Cost = 0 blocking, ~1 process + ≤6
`ps` forks resident. Nothing to reclaim here.

---

# PART B — PER-HOOK COST

## B1. Isolated per-hook timing (synthetic SessionStart JSON on stdin)

Harness `/tmp/ssprobe/hookbench/bench.py`: `subprocess.run(cmd, input=payload, cwd=<reso worktree>)`,
`perf_counter` around each call, `CC_PANE_ID` / `ITERM_SESSION_ID` / `CLAUDE_CODE_TASK_LIST_ID`
stripped (R4's method), n=5. Payload:
`{"session_id":"00000000-dead-beef-…","transcript_path":"/tmp/ssprobe/fake-transcript.jsonl","cwd":"…","hook_event_name":"SessionStart","source":"startup","permission_mode":"auto"}`

```
N=5 BENCH_ENV="CLAUDE_CONFIG_DIR=/Users/chrisren/.claude-tertiary" \
  python3 /tmp/ssprobe/hookbench/bench.py /tmp/ssprobe/hookbench/cmds.json
```

| Hook | med ms (throwaway cfg) | **med ms (real cfg `.claude-tertiary`)** | runs (real) |
|---|---|---|---|
| setup-task-symlinks.sh | 74 | **242** | 290/235/301/242/240 |
| pre-session-validate.sh | 125 | **180** | 180/123/128/182/185 |
| activation-watch.sh | 127 | **129** | 131/125/129/129/127 |
| dod-persist.sh | 128 | **127** | 127/128/127/124/127 |
| session-index-start.sh | 130 | **127** | 127/132/128/126/122 |
| config-mirror-assert.sh | 5 | **77** | 126/73/77/125/70 |
| live-session-registry.sh | 73 | **74** | 69/74/70/128/77 |
| setup-plan-symlinks.sh | 76 | **75** | 75/73/74/75/76 |
| session-start.sh | 73 (first run 2 655 — cold MCP SWR) | **74** | 72/78/76/70/74 |
| mailbox-drain.sh session-start | 38 | **40** ← **FALSE. See B3.** | 41/37/40/40/40 |
| lead-crash-watchdog.sh | 40 | **40** | 40/38/39/125/38 |
| session-register.sh | 39 | **40** | 40/37/40/39/40 |
| frontier-status.sh | 40 | **40** | 40/37/40/39/40 |
| desk-brief-inject.sh | 20 | **20** | 21/20/21/20/20 |
| mailbox-wake-arm.sh | n/a — `asyncRewake`, see A4 | **0 blocking** | backgrounded |

Two config-dir sensitivities worth naming: `setup-task-symlinks` 74→242 ms and
`config-mirror-assert` 5→77 ms. The latter is structural — it `exit 0`s unless
`CLAUDE_CONFIG_DIR` matches `$HOME/.claude-*`, so **it costs literally 0 for account 1 and
~77 ms for accounts 2-5** (the ones the fleet actually launches).

## B2. IN-SITU per-hook timing under real harness concurrency

Real `~/.claude/settings.json` SessionStart block copied verbatim into the throwaway cfg, each
command wrapped in `/tmp/ssprobe/tw.sh <name> env CLAUDE_CONFIG_DIR=~/.claude-tertiary …`
(a `perl -MTime::HiRes` clock either side; `CC_WAKE_ARM=0` only on mailbox-wake-arm so the probe
cannot leave a 4 h watcher behind). Clocks aligned to the pty's session t0.

```
   setup-task-symlinks.sh     start= 0.938 end= 1.571 dur= 0.633
   pre-session-validate.sh    start= 0.948 end= 1.281 dur= 0.333
   activation-watch.sh        start= 0.956 end= 1.254 dur= 0.298
   session-index-start.sh     start= 0.980 end= 1.242 dur= 0.262
   session-register.sh        start= 0.939 end= 1.183 dur= 0.244
   config-mirror-assert.sh    start= 0.971 end= 1.195 dur= 0.224
   dod-persist.sh             start= 0.954 end= 1.155 dur= 0.201
   session-start.sh           start= 0.940 end= 1.099 dur= 0.159
   frontier-status.sh         start= 0.970 end= 1.121 dur= 0.151
   lead-crash-watchdog.sh     start= 0.951 end= 1.100 dur= 0.148
   desk-brief-inject.sh       start= 0.969 end= 1.091 dur= 0.122
   setup-plan-symlinks.sh     start= 0.938 end= 1.057 dur= 0.118
   live-session-registry.sh   start= 0.970 end= 1.057 dur= 0.087
   mailbox-wake-arm.sh        start= 0.968 end= 1.003 dur= 0.035
   ── mailbox-drain.sh: NEVER LOGGED AN END LINE ──
   LAST LOGGED HOOK ENDS AT 1.571 s;  /help rendered at 5.959 s
```

Every hook is ~1.3-2× its isolated time under 14-way concurrency (fork storm + 24 live sessions),
but **all 14 finish inside 640 ms**. The session was still frozen for another 4.4 s.

## B3. 🚨 THE ANSWER: `mailbox-drain.sh session-start` is killed at its 5 s timeout, every start

`/help` lands at hook-start **+ 5.000 s** in every run. The wrapper's START line is written and the
END line never is ⇒ the process is **reaped by the harness at `timeout: 5`** and its work is thrown away.

### Isolation A/B (in situ, n≥2 each, `/help` render time)

| SessionStart config | `/help` at |
|---|---|
| no hooks | **1.39 / 1.41 / 1.42 / 1.54 s** |
| all 14 hooks EXCEPT mailbox-drain | **1.39 / 2.45 s** |
| **mailbox-drain ALONE** | **5.40 / 5.45 / 5.74 / 6.39 s** |
| mailbox-drain alone, **`ITERM_SESSION_ID` unset** | **1.38 / 1.45 s** |

### Why every previous measurement missed it — the pane-env artifact

`hooks/mailbox-drain.sh:87`:
```bash
case "$own_pane" in ''|*[!0-9A-Fa-f-]*) exit 0 ;; esac
```
`own_pane` is `${CC_PANE_ID:-${ITERM_SESSION_ID:-}}`. **R4's harness — and my own B1 bench —
ran `env -u CC_PANE_ID -u ITERM_SESSION_ID`, so the hook exited at line 87 in 38 ms without
doing anything.** R4's "`mailbox-drain.sh session-start` 0.02 s ×3" is not a measurement of this
hook; it is a measurement of its early-exit guard. Every real session HAS a pane.

### True cost, measured against a COPY of the mailbox (`/tmp/ssprobe/mbx`, 3 091 entries)

```
CC_MAILBOX_DIR=/tmp/ssprobe/mbx CLAUDE_CONFIG_DIR=~/.claude-tertiary \
ITERM_SESSION_ID=w0t0p0:<pane> /usr/bin/time -p ~/.claude/hooks/mailbox-drain.sh session-start <<< '<payload>'
```

| pane | trail entries | wall |
|---|---|---|
| synthetic, 1st run (no predecessor yet) | 1 | **~0.15 s** |
| synthetic, after reuse | 9 | **19.08 / 21.75 / 16.63 s** |
| real pane `101` | 2 | **20.2 s** |
| real pane `100` | 3 | **15.3 s** |
| any pane, `ITERM_SESSION_ID` unset | — | 0.036–0.039 s (early exit) |

### Root cause, localised to one statement

`PS4='+${SECONDS}s:${LINENO} ' bash -x hooks/mailbox-drain.sh session-start` →
```
  +20s  after mailbox-drain.sh:243  mailbox_adoptable_predecessors <pane> <sid>
```

`hooks/lib/mailbox-pending.sh:548 mailbox_session_is_current()` is an **O(all alias files)**
scan with **two forks per file**:
```bash
for f in "$(_mbx_alias_dir)"/*; do
  [ -f "$f" ] || continue
  tip="$(tail -n1 "$f" 2>/dev/null | awk '{print $2}')"   # 2 forks × N files
  [ "$tip" = "$sess" ] && return 0
done
```
`.alias` holds **1 300** files today. One *miss* therefore costs **5.0 s** measured:
```
bash -c '. ~/.claude/hooks/lib/mailbox-pending.sh; mailbox_session_is_current deadbeef-…-000000000000'
# → 5 s, rc=1
```
`mailbox_adoptable_predecessors` calls it **once per trail candidate**, and its `max=3` bound
counts only *adoptable results*, not candidates scanned — a candidate that IS current
`continue`s without decrementing anything. So cost ≈ (trail predecessors) × up to 5 s.

**Who pays:** 488 of 1 300 panes (**37 %**) already carry ≥1 predecessor, and every `/clear`,
recycle, handoff-into-the-same-pane and resume appends one more. A brand-new pane is fast; a
*reused* pane — the fleet's normal case — is not. Both `.alias` (1 300) and the trail grow
monotonically, so **this gets worse every day**. It is the exact pathology R4 found in
`setup-task-symlinks` (21 s work, 5 s cap, output discarded) reincarnated in another hook.

**Cost to the operator: a hard 5.000 s, on the critical path, at every session start on a reused
pane — and the hook's actual job (draining peer mail) does not get done.**

## B4. The layer's TOTAL blocking contribution — paired A/B, in situ

Same pty harness, `/help` render time, alternating configs, clean pane env:

| SessionStart config | `/help` at (s) | n |
|---|---|---|
| **no hooks** | 1.408 / 1.422 / 1.382 / 1.377 / 1.410 / 1.421 / 1.535 → **median 1.410** | 7 |
| **14 hooks, mailbox-drain removed** | 1.408 / 1.407 / 1.387 / 1.402 / 1.391 / 2.453 → **median 1.402** | 6 |
| **all 15 hooks** | 5.431 / 5.404 / 5.595 / 5.424 / 5.416 / 5.401 / 5.959 → **median 5.424** | 7 |

- **14 of 15 hooks add 0 ms measurable** — they finish (≤640 ms in situ) *under* the harness's own
  ~1.4 s pre-prompt floor, so they are **CONCURRENT / absorbed**, not additive. On the operator's
  real config (6 MCP servers, 93 skills, 129–184 KB `.claude.json`) that floor is *higher* still
  (R4 measured 5.7 s to first API dispatch), so the absorption margin is larger, not smaller.
- **`mailbox-drain.sh` alone adds `median 5.424 − 1.410` = +4.01 s.**

**⇒ `layer_blocking_ms_median` for sessionstart-hooks = ~4 010 ms, and 100 % of it is one hook.**

## B5. The fix, magnitude-checked

`mailbox_session_is_current` re-derives the whole tip set on *every* call, 2 forks per alias file.
Computing the tip set **once, in one awk pass** over the same 1 300 files:

```
/usr/bin/time -p bash -c 'awk "FNR==1{if(NR>1)print p} {p=\$2} END{print p}" ~/.claude/mailbox/.alias/* | sort -u | wc -l'
# real 0.04 / 0.04 / 0.04
```

**40 ms vs 5 000 ms per lookup — ~125×.** Hoisting the tip set to a single pass (and bounding the
*candidate* scan, not just the adoptable-result count) takes the hook from a 5 s timeout kill to
roughly its no-pane cost (~40–150 ms) and — importantly — lets it actually **finish its job**, which
today it never does on a reused pane.

---

# PART C — VALUE / DEFERABILITY per expensive hook

| Hook | in-situ ms | class | what it delivers AT SessionStart | (i) defer to 1st prompt | (ii) background | (iii) cache | (iv) delete |
|---|---|---|---|---|---|---|---|
| **mailbox-drain.sh** | **5 000 (killed)** | **BLOCKING** | drains peer mail into the first turn's context + arms/nudges the wake path. Genuinely load-bearing for fleet 2-way comms. | ✗ — mail must be in the *first* turn's context | partially: adoption yes, own-box take no | **YES — this is the fix** (hoist the alias-tip set) | ✗ **NEVER** — this is the cross-session comms rail |
| setup-task-symlinks.sh | 633 | CONCURRENT | regenerates the ACTIVE list's `TASKS.md`; index prune + GC already self-detached (R6) | ✓ | already partly | ✓ | ✗ (TASKS.md is read in-session) |
| pre-session-validate.sh | 333 | CONCURRENT | auto-rolls back `~/.claude-versions/current` if the promoted binary is broken | ✗ — it guards the launch itself, but it is **already too late** (the binary is running) | ✓ | ✓ (stamp per version) | ✗ — genuine safety net for auto-upgrade |
| activation-watch.sh | 298 | CONCURRENT | re-pages staged-but-un-run operator activation scripts (absence-is-loud) | ✓ | ✓ | ✓ | ✗ — load-bearing fleet discipline (C10 ceiling) |
| session-index-start.sh | 262 | CONCURRENT | injects recent-session context; DB stub row **already backgrounded** (`( … ) &`). Blocking half = one `python3 session-search.py --context-inject` over a 41 MB / 3 983-row sqlite | ✗ (context must be in turn 1) | stub already is | ✓ | ✗ |
| session-register.sh | 244 | CONCURRENT | writes `~/.claude/cc-registry/<pane>.json` so peers can address this pane | ✗ — a peer may address it before the first prompt | ✓ | ✗ | ✗ — addressing rail |
| config-mirror-assert.sh | 224 | CONCURRENT | re-asserts the knowledge-layer symlink mirror for accounts 2-5 (0 ms for account 1). Its own header says it *"fixes the NEXT session, not the running one"* | **✓ — by its own admission** | ✓ | ✓ | belt-and-suspenders only; the zsh launcher is primary |
| dod-persist.sh | 201 | CONCURRENT | re-injects the frozen `Scope (frozen):` DoD as additionalContext | ✗ (turn-1 context) | ✗ | ✓ | ✗ — load-bearing for close integrity |
| session-start.sh | 159 (**2 655 cold**) | CONCURRENT | MCP health line, served stale-while-revalidate (TTL 300 s, MAX_AGE 86 400 s). Beyond MAX_AGE it probes **inline** = 2.65 s | — | refresher already detached | already cached | ✗ |
| frontier-status.sh | 151 | CONCURRENT | ≤1 line frontier-window / open-holes nudge | ✓ | ✓ | ✓ | routing discipline; cheap enough to leave |
| lead-crash-watchdog.sh | 148 | CONCURRENT | spawns the detached watchdog daemon (`setsid`+`nohup`+`disown`) | ✗ | already detaches its daemon | ✗ | ✗ |
| desk-brief-inject.sh | 122 | CONCURRENT | re-injects the desk role brief iff this pane holds the desk role | ✗ (turn-1 context) | ✗ | ✓ | ✗ |
| setup-plan-symlinks.sh | 118 | CONCURRENT | plan symlinks, one awk pass over 254 plans (R6 rewrite) | ✓ | ✓ | ✓ | ✗ |
| live-session-registry.sh | 87 | CONCURRENT | positive liveness PID so worktree-gc cannot reap a live worktree | ✗ — the reaper can run at any moment | ✓ | ✗ | ✗ — data-loss guard |
| mailbox-wake-arm.sh | 35 | **BACKGROUNDED** | arms the ≤4 h `cc-await-ping` inbox watcher; `asyncRewake:true` ⇒ 0 blocking (proved A4) | n/a | already | n/a | ✗ |

**Honest verdict on "delete":** none of the 14 cheap hooks is worth deleting for latency — together
they measure **0 ms** of blocking cost, and most are load-bearing fleet discipline (addressing,
liveness, DoD, activation queue, wake path). Deleting any of them buys nothing and costs a rail.
**The entire win is one 40-line fix inside `mailbox_session_is_current`.**

---

# PART D — PRIOR-ART VERDICT

| Prior claim (R4 / R6) | status today |
|---|---|
| SessionStart hooks BLOCK | **HOLDS, and is stronger** — they block the *whole input pipeline*, including local slash commands, not just the first API dispatch. They do **not** block first paint (~0.45 s). |
| Hooks run CONCURRENTLY; group cost = MAX not SUM | **HOLDS** — direct timestamps: 4 hooks, 2 matcher groups, STARTs within 0.44 ms; 4× sleep-3 = 3.03 s wall. |
| `setup-task-symlinks.sh` 21 s → 237 ms (R6) | **HOLDS** — 242 ms isolated, 633 ms in situ. |
| `session-start.sh` 2.52 s → 0.036 s via MCP SWR | **HOLDS warm** (74 ms). ⚠️ the *cold/expired* path still probes inline: measured **2 655 ms** on a cold cache. |
| `activation-watch.sh` 660–900 → 126 ms | **HOLDS** — 129 ms. |
| `setup-plan-symlinks.sh` 560 → 69 ms | **PARTLY** — 75 ms isolated (close), 118 ms in situ. |
| "group max ~240 ms; everything this fleet contributes to startup is sub-second" | **STALE — REFUTED.** True of the 14 hooks R6 measured; false for the layer, because R6's own harness stripped `ITERM_SESSION_ID` and so never ran `mailbox-drain`'s real path. Real group cost = **5.0 s**. |
| `mailbox-drain.sh session-start` = 0.02 s | **STALE — it is a measurement of the early-exit guard**, not of the hook. Real cost 15–22 s, capped at 5 s. |
| `~/bin/claude-latest` → `~/.claude-versions/current` is the launch path | **STALE for the fleet** — `current` is 2.1.114 and **0 live sessions run it**; all 36–38 run `~/.claude-220/…/claude`. |

# PART E — UNKNOWNS / not measured

- Whether the harness's `timeout` kill of a SessionStart hook is a SIGTERM or SIGKILL, and whether
  `mailbox-drain` leaves a partially-advanced cursor when reaped mid-`mailbox_take_n`. **UNKNOWN.**
- The exact live-fleet lock contention on the mailbox `flock` with ~24 concurrent sessions — all
  15–22 s numbers above were taken against a **COPY** of the mailbox dir precisely to exclude it,
  so the live figure is ≥ these. **UNKNOWN (lower-bounded).**
- The `/help`-render proxy measures time-to-*local*-command; time-to-first-*API*-token was not
  re-measured today (no `claude -p` probe was spent). R4's 5.7 s figure for that is not re-derived.
- Per-config-dir variation across all 5 mirrored dirs: only `.claude-tertiary` (real) and a
  throwaway were measured.
