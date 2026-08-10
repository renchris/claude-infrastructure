# Axis F — Hook economics (measured)

**Scope:** per-event fork/wall bill of the 79 registered hook entries across 12 events; broad-vs-narrow
matchers; per-fire store reads; dispatcher-consolidation design; hooks that spawn background children.
**Method:** every figure is a **median of 9–21 interleaved A/B iterations** against a `bash -c :`
control, timed with the bash **`time` keyword** (a builtin — the measured value carries **no
wrapper-fork bias**, unlike the `subprocess.run` method whose ~2× inflation `HOOK_CHAIN_COST.md` §2.1
had to retract). Fork counts are **live exec counts** from a counting PATH shim, never static `$(`.
Replica invocations only: synthetic session id `00000000-dead-beef-…`, throwaway git repo at
`/private/tmp/hookbench/repo`, state-dir seams redirected, side-effecting binaries stubbed.
`settings.json` and `hooks/` unmodified.
**Positive control:** `bash -c 'sleep 0.05'` measured **+58.0 ms** against the control; `/usr/bin/true`
measured **±0.0 ms**. The control held **5–9 ms across load 40→141** for the whole session, so
cross-block comparisons are sound.
**Load is recorded per block** (`uptime` before/after). Blocks ran at load **40–106**; the box hit
**141** during the wave.

---

## 0. Verdict first — this axis is NOT the memory bottleneck, and the measurement says so

| Resource | Hook layer's share | Basis |
|---|---|---|
| **RAM (steady state)** | **~68 MB of 64 GB = 0.10%** | 32 leaked `lead-crash-watchdog.sh` daemons (§5). Transient hook processes average **<1 concurrent** fleet-wide. |
| **CPU** | **0.20 cores mean · ~0.7 cores peak-hour** (2.0%–7% of 10 cores) | §3 |
| **Turn latency** | **1.2%** — 5.1 s of hook wall in a **443 s** median turn | §3.3 |
| **Process spawns** | **18/s mean, 54/s peak**, fleet-wide | §3.2 |

**The consolidation the brief asks me to design should not be built.** I reached that independently of
`docs/plans/HOOK_CHAIN_COST.md` (which rejected the broker and measured the collapse negative) and from
the *opposite* direction: I measured the four events that document never measured — **Stop,
UserPromptSubmit, SessionStart, and the match-all PostToolUse matcher** — found costs **5–10× larger
than anything it recorded**, and the total is *still* third-order for RAM. A dispatcher would put one
shared failure dependency in front of 79 entries to reclaim a fraction of 0.2 cores.

**Three things are worth doing** (§6), and none is a dispatcher: a leaked daemon (68 MB, growing), two
hooks that can block a tool for **10 minutes** because they declare no timeout, and one SessionStart
backstop that spends **2.68 s and 433 forks** re-doing what the launcher already did.

---

## 1. The registered surface (live, `~/.claude/settings.json`, 1099 lines)

**79 hook entries** across 12 events — not 41; 41 is the *matcher-group* count and understates the
process count by 1.9×. No other settings file contributes hooks (project
`.claude/settings.json` and `.claude/settings.local.json` both declare **0**), so this is the whole
surface.

| Event | entries | matcher breadth |
|---|---|---|
| PreToolUse | 14 | 5 groups, all **narrow** (`Bash` 7 · `Write\|Edit\|MultiEdit` 3 · `Agent` 2 · ms365 1 · `AskUserQuestion` 1) |
| SessionStart | 14 | n/a (fires always) |
| PostToolUse | 12 | `Bash` 3 · `Write\|Edit\|MultiEdit` 4 · **match-all `""` 3** · `TaskCreate\|TaskUpdate` 1 · `ExitPlanMode` 1 |
| Stop | 11 | fires always |
| SessionEnd | 7 | fires always |
| UserPromptSubmit | 6 | fires always |
| Notification | 5 | narrow (3 distinct notification types) |
| PermissionRequest | 4 | 3 narrow + **1 match-all** |
| PreCompact | 3 | `auto` / `manual` |
| TeammateIdle · WorktreeCreate · TaskCompleted | 1 each | fires always |

**Broad matchers — the complete list (4).** Only these fire on tool calls they were not written for:

| Event | hook | timeout | consequence |
|---|---|---|---|
| PostToolUse `""` | `teammate-checkpoint.sh` | 10 s | fires on **every** tool call of every session |
| PostToolUse `""` | `cc-permission-beacon.sh clear` | 5 s | ditto |
| PostToolUse `""` | `mailbox-drain.sh post-tool` | 5 s | ditto |
| PermissionRequest `""` | `cc-permission-beacon.sh write` | 5 s | every permission prompt |

Matcher hygiene is otherwise **good**: all 14 PreToolUse entries and 9 of 12 PostToolUse entries are
tool-scoped. There is no narrowing win available on PreToolUse at all.

---

## 2. Hooks run in PARALLEL — settling prior art's named-unresolved question

`HOOK_CHAIN_COST.md` §8 closes with: *"says nothing about whether Claude Code runs a chain serially or
in parallel — **Unresolved, and named as unresolved**."*

**Resolved: parallel.** Anthropic's hooks reference states verbatim *"All matching hooks run in
parallel."* (<https://code.claude.com/docs/en/hooks>). Same source: matching handlers defined in more
than one settings file are **de-duplicated**; timeouts are **per-hook** with a 600 s default for
`command` hooks (UserPromptSubmit lowers it to 30 s); **SessionEnd hooks share a 1.5 s budget**;
PreToolUse and Stop **can block**, PostToolUse cannot veto (the tool already ran) — though the harness
still awaits it, which local evidence confirms: `mailbox-drain.sh post-tool` injects context and
`waiting-recycle.sh` returns advisories that demonstrably reach the model.

**So the correct latency unit is the burst wall, not the serial sum** — and I measured both. Parallelism
recovers ~2.2–2.7×, not the ~11× that `max(hook)` would predict, because N concurrent processes contend:
Stop's slowest single hook is 691 ms but the 11-way burst walls at **934 ms** — a **1.35× self-contention
factor**.

| Event group | serial sum | **burst wall (what CC pays)** | p95 burst | recovery |
|---|---|---|---|---|
| PreToolUse / `Bash` (7) | 397 ms | **179 ms** | 233 ms | 2.2× |
| PostToolUse / `Bash` + match-all (6) | 331 ms | **151 ms** | 169 ms | 2.2× |
| UserPromptSubmit (6) | 621 ms | **228 ms** | 266 ms | 2.7× |
| Stop (11) | 2,202 ms | **934 ms** | 1,568 ms | 2.4× |
| SessionStart (**7 of 14** — safe subset) | 4,749 ms | **2,459 ms** | 2,909 ms | 1.9× |

The serial sum remains the correct **CPU and fork** unit. Both columns are load-conditional.

---

## 3. Per-event table — measured wall, measured forks

### 3.1 PreToolUse / `Bash` — 7 hooks, fires before every Bash call (**and can block it**)

| hook | ms scratch | ms **real repo** | ext execs (live) | dominant execs | timeout |
|---|---|---|---|---|---|
| `validate-bash.sh` | 132 | **174** | **23** | `grep`×14, `sed`×3, `jq`×2 | 10 s |
| `qos-rewrite.sh` | 120 | **126** | **15** | `grep`×8, `sed`×2, `dirname`×2 | 10 s |
| `git-worktree-guard.sh` | 46 | 49 | 3 | `sed`×2, `jq`×1 | 10 s |
| `keychain-guard.sh` | 34 | — | 1 | `jq`×1 | ⚠ **none → 600 s** |
| `curl-gate-scope.sh` | 22 | 28 | 2 | `readlink`, `dirname` | 5 s |
| `ship-rail-push-allow.sh` | 22 | — | 2 | `jq`, `grep` | 5 s |
| `rm-safe-allowlist.sh` | 21 | — | 2 | `jq`, `grep` | 5 s |
| **total** | **397** | | **48** | | |

`curl-gate-scope.sh` is registered (M1 shipped; migration `0002-curl-gate-scope-registration.sh`), and
it works: 2 execs, 22 ms, versus the 35–46 ms `curl-gate.py` it replaced.

### 3.2 PostToolUse — 3 on `Bash`, 4 on `Write|Edit`, **3 match-all**

| matcher | hook | ms | execs | timeout |
|---|---|---|---|---|
| `Bash` | `waiting-recycle.sh` | 127 | ~13 | ⚠ **none → 600 s** |
| `Bash` | `log-bash.sh` | 46 | 5 | 5 s |
| `Bash` | `relay-verbatim.sh` | 17 | 2 | 5 s |
| **`""`** | `mailbox-drain.sh post-tool` | **75** | — | 5 s |
| **`""`** | `teammate-checkpoint.sh` | 36 (p95 **656** in the real repo) | 8 | 10 s |
| **`""`** | `cc-permission-beacon.sh clear` | 30 | 3 | 5 s |
| `Write\|Edit` | `validate-plan-structure.sh` · `plan-version-commit.sh` · `plan-index-update.sh` · `post-file-edit.sh` | 34 · 30 · 23 · 18 | — | 10/10/5/30 s |

PreToolUse `Write|Edit`: `backup-before-write.sh` 66 ms · `check-edit-boundary.sh` 64 ms ·
`plan-agent-teams-default.sh` 22 ms = **152 ms**.

**The match-all trio costs 141 ms and ~14 execs on every tool call that is not Bash and not an edit** —
12.1% of all tool calls (§4). That is the population `HOOK_CHAIN_COST.md` R-7 said nothing could measure.

### 3.3 Stop — 11 hooks, every turn end (**can block**)

Two independent passes at different loads; both shown because the spread *is* the finding.

| hook | pass 1 (load 100) | pass 2 (load 79) | execs | timeout | headroom at p95 |
|---|---|---|---|---|---|
| `session-continue.sh` | **1,085** | **691** | **38** (`git`×9, `jq`×5, `mkdir`×4) | 5 s | p95 1,752 ms = **35%** |
| `operator-readout.sh` | 518 | 389 | 11 | 10 s | 6% |
| `boundary-handoff.sh` | 453 | 330 | 11 | 5 s | 10% |
| `dispatch-assert.sh` | 359 | 325 | 9 | 10 s | 6% |
| `session-beat.sh stop` | 135 | 167 | **23** (`ps`×8, `tr`×4, `jq`×4) | 5 s | 4% |
| `teammate-checkpoint.sh` | 106 | 57 | 8 | 10 s | — |
| `anti-deference-nudge.sh` | 77 | 94 | 9 | 5 s | — |
| `completion-assert.sh` | 73 | 92 | 9 | 5 s | — |
| `cc-permission-beacon.sh clear` | 26 | 32 | 3 | 5 s | — |
| `cache-expiry-tracker.sh` | 13 | 21 | 1 | 5 s | — |
| `notify.sh complete` | **963** (p95 2,650) | **4** | 4 | 5 s | ⚠ p95 **53%** |
| **total** | **3,808** | **2,202** | **124** | | |

`notify.sh` is **bimodal, not noisy**: 4 ms on the debounced path, up to 2,650 ms when it actually
notifies, because `notify.sh:306` makes a **synchronous** `osascript display notification` AppleEvent
into NotificationCenter, bounded only by `timeout 5`. Its `afplay` sibling two lines earlier
(`:292–296`) is already `&`-backgrounded and `disown`ed. One character of asymmetry.

### 3.4 SessionStart — 14 hooks; 7 timed, 7 excluded as unsafe

| hook | ms | ext execs | dominant execs | timeout | headroom |
|---|---|---|---|---|---|
| `config-mirror-assert.sh` | **2,680** | **433** | **`readlink`×431** | 8 s | p95 2,859 = **36%** |
| `activation-watch.sh` | **1,592** | **211** | `basename`×98, `head`×39, `grep`×39 | 5 s | p95 1,861 = **37%** |
| `pre-session-validate.sh` | 168 | 9 | `python3`×1 | 10 s | — |
| `mailbox-drain.sh session-start` | 107 | — | — | 5 s | — |
| `dod-persist.sh` | 76 | 6 | — | 5 s | — |
| `frontier-status.sh` | 76 | 11 | — | 5 s | — |
| `desk-brief-inject.sh` | 50 | 5 | — | 5 s | — |
| **subtotal (7 of 14)** | **4,749** | **675** | | | |

**Excluded, not measured** — running them would mutate live fleet state: `lead-crash-watchdog.sh`
(**spawns a resident daemon**), `session-register.sh` + `session-index-start.sh` (background children +
registry writes), `live-session-registry.sh`, `session-start.sh`, `setup-plan-symlinks.sh`,
`setup-task-symlinks.sh`. The real SessionStart total is therefore **≥ 4.7 s serial / ≥ 2.5 s burst and
≥ 690 processes**.

`config-mirror-assert.sh` is 16 lines; the cost is entirely `:14`, a `zsh -fc` that sources
`config-mirror.zsh` and `_cc_sync_account` — one `readlink` per mirrored file. **It exits in ~5 ms when
`CLAUDE_CONFIG_DIR` is unset** (`:10`), so account 1 pays nothing and every other account pays the full
2.68 s. Live: 7 `claude-next` + 2 `claude-fable` launchers, all non-default ⇒ **the fleet is on the
expensive branch**. Its own header calls it *"belt-and-suspenders… the launcher wrapper is the primary
mechanism."*

### 3.5 Not measured, and why

`SessionEnd` (7) — every member deregisters/reaps live sessions. Note the docs' **1.5 s shared budget**
for the whole event: a 7-hook chain against a 1.5 s cap is worth a dedicated check by whoever owns it.
`Notification` (5) and `PermissionRequest` (4) — real desktop pages. `PreCompact` (3), `TeammateIdle`,
`WorktreeCreate` (180 s timeout), `TaskCompleted` (120 s timeout) — rare or state-mutating.

---

## 4. The multiplied bill

**Rates — R-7 closed.** `HOOK_CHAIN_COST.md` R-7: *"No census of ALL-tool calls exists, only of Bash…
needs a tool-call counter before any match-all hook's cost can be stated per-hour."* Two independent
sources, 24 h, all five `~/.claude*/projects` config dirs (169 sessions, 16,481 `tool_use` blocks):

| | value |
|---|---|
| Tool mix | **Bash 76.7%** · `Edit\|Write\|MultiEdit` 11.3% · other 12.1% |
| Fleet Bash rate (`bash-execution.log`, 9.41 h window, 101 sessions) | **744/h** mean · 646 median-hour · **2,250 peak-hour** |
| All-tool rate, derived (744 ÷ 0.767) | **971/h** |
| All-tool rate, transcript-direct | **829/h** mean · 901 median · 2,448 peak |
| Prompts/turns per hour | 32 mean · 22 median · 86 peak |
| Tool calls per turn | **12 median · 27.9 mean** |
| Turn duration | **443 s median** · 780 s mean · 2,102 s p90 (n=416) |

The two all-tool estimates (971 vs 829) agree within 15%; use **~900/h mean, ~2,500–2,900/h peak**.
⚠ `bash-execution.log` **rotated at 2026-08-09T22:21Z**, so its window is 9.4 h, not the 39 h
`HOOK_CHAIN_COST.md` §2.4 quotes — that document's 480/h is stale and today's rate is **1.55× higher**.

**Per Bash tool call:** 179 ms (pre-burst) + 151 ms (post-burst) = **330 ms latency**; **728 ms CPU**
across **13 hook processes + ~73 external execs ≈ 86 processes**.

**Fleet CPU (10-core box):**

| stream | rate | × cost | s/h |
|---|---|---|---|
| Bash tool calls | 744/h | 728 ms | 542 |
| Stop | 32/h | 2,202 ms | 70 |
| SessionStart | ~7/h (170/day) | 4,749 ms | 33 |
| UserPromptSubmit | 32/h | 621 ms | 20 |
| Edit/Write | 110/h | 257 ms | 28 |
| other tools (match-all only) | 117/h | 141 ms | 16 |
| **total** | | | **709 s/h = 0.197 cores (2.0%)** |

Peak hour (2,250 Bash/h) → 1,758 s/h = 0.49 cores; hook ms inflate ~1.5× at peak load ⇒ **~0.7 cores
(7%)**. Larger than `HOOK_CHAIN_COST.md` §2.4's 0.054–0.149 cores — because it counted only
`matcher:"Bash"` hooks, at a lower rate, at load 16 — and **still third-order**.

**Process-spawn rate:** 744/h × 86 = **64,000 processes/h = 17.8/s** fleet-wide; **54/s at peak**.
A **15-agent wave fires ~10,000 processes in one SessionStart burst** (15 × ~690) — the sharpest
concentration in the whole layer, and it lands exactly when the box is most loaded.

**Why this is not a RAM story.** Mean concurrent hook processes = rate × burst wall =
(971/3600) × 0.33 s ≈ **0.09 chains in flight**; even at peak, with Stop and SessionStart added, the
fleet averages **<5 concurrent hook processes ≈ 10 MB**. Hooks are born and die too fast to hold RAM.
And the indirect chain — *latency → longer turns → more concurrent sessions resident* — is worth
**1.2%**: 5.1 s of hook wall in a 443 s median turn (12 × 330 ms + 228 + 934). At the 27.9-call mean it
is 10.4 s in a 780 s turn = 1.3%. **Both denominators give the same answer, so the indirect argument
does not rescue this axis either.**

---

## 5. Background children — question (e), counted live via ppid

**Static census (10 hooks contain a bg-spawn site).** Only one leaves a **resident**:

| hook | spawn shape | resident? |
|---|---|---|
| `lead-crash-watchdog.sh:1184` | `) </dev/null >/dev/null 2>&1 &` + `disown` | ⚠ **YES — one 30 s-poll daemon per SessionStart** |
| `session-beat.sh:113,115` | worker `&` + `( sleep 3; kill -9 ) &` watchdog | no — `wait`ed and killed (`:117–119`) |
| `session-register.sh:315,317,351` | same pattern + `( … & ) &` | no (bounded) |
| `session-end.sh:68,195` · `session-index-start.sh:78` · `plan-version-commit.sh:88` · `teammate-auto-shutdown.sh:1243` | `) &` (+`disown` on two) | transient |
| `notify.sh:292–296` | `afplay … &` + `disown` | transient (sound duration) |

**Live count:** `ps -eo pid,ppid,rss,etime | grep lead-crash-watchdog` → **32 processes, 28 of them
ppid 1, 68,368 KB total RSS**, ages **50 s → 1 h 07 m**. Spawn log
(`~/.claude/logs/lead-crash-watchdog.log`, 2.8 MB, since 2026-04-17): **5,742 spawns**, ~102–466/day
(466 on 2026-08-07).

The exit protocol is sound on paper — pidfile-gone, SUPERSEDED, lead-crash, identity-lost, all polled
every 30 s (`:898–941`). But **32 daemons against ~15–20 live sessions** means roughly half are watching
something that is gone. The script's own comment is the tell: *"0 'retired stale watchdog' lines across
3864 spawns say it never has"* — the spawn-guard's reap path has **never once fired**.

Cost: **68 MB resident and monotonically growing within a boot**, plus 32 × 2 wakes/min = **64
wakes/min** of pure poll. This is the **only** durable RAM the hook layer holds.

---

## 6. Findings

**Finding: `lead-crash-watchdog.sh` leaks one resident daemon per session start**
Evidence: 32 live, 28 at ppid 1, 68,368 KB RSS, ages 50 s–1 h 07 m, vs ~15–20 live sessions; 5,742 spawns logged; the script's own note records the stale-reap path has fired 0 times in 3,864 spawns (`hooks/lead-crash-watchdog.sh:898–941`, `:1184`)
Cost now: 68 MB + 64 poll-wakes/min; grows with every handoff/recycle until reboot
Re-architecture: the 30 s poll already reads `$WATCHDOG_DIR/$sid.pid` — add a **liveness sweep at spawn time** (a new watchdog reaps any `*.daemon` whose recorded `{pid,lstart}` is dead) and a hard TTL. Not a new daemon: the reap runs inside the SessionStart hook that already exists.
Sizing: recovers ~68 MB now and prevents unbounded growth · effort **S** · risk **low** (the reaped process is by construction watching a dead lead). **RAM-positive but small — file it, do not headline it.**
Existing mechanism: `daemon_alive` + `$DAEMON_FILE` at `:780–793` — **EXTEND**, the guard exists and is simply never reached.

**Finding: two hot-path hooks declare no timeout and inherit the 600 s default**
Evidence: `settings.json` — `keychain-guard.sh` (PreToolUse/`Bash`, **the blocking path**) and `waiting-recycle.sh` (PostToolUse/`Bash`) are the only 2 of 79 entries with no `timeout` key; per Anthropic's reference the `command` default is **600 s**
Cost now: 0 today (measured 34 ms / 127 ms) — this is a **tail-risk**, not a throughput cost. A `keychain-guard.sh` that blocks on a Keychain prompt or a wedged `security` call can stall a session's next Bash call for **10 minutes**, and PreToolUse is the one event that can block.
Re-architecture: add `"timeout": 5` and `"timeout": 10`. Two JSON keys.
Sizing: effort **XS** · risk **low** · directly addresses the repo's own `bounding-external-calls` and "43 wrappers pinned 10 h by one orphan" scars
Existing mechanism: the other 77 entries already carry explicit timeouts — this is **consistency**, not new policy.

**Finding: SessionStart costs ≥2.5 s and ≥690 processes, and 4.3 s of it is two hooks**
Evidence: `config-mirror-assert.sh` **2,680 ms / 433 execs (431 × `readlink`)**; `activation-watch.sh` **1,592 ms / 211 execs (98 × `basename`)**; 7-hook burst walls at 2,459 ms (p95 2,909)
Cost now: ~170 session starts/day ≈ **13 min/day** and ~117,000 processes/day; a 15-agent wave = **~10,000 processes in one burst**, at peak load
Re-architecture: (a) `config-mirror-assert.sh` is a **backstop for what the launcher already did** (its own `:2–7`) — damp it to once per account per boot with a stamp file, or drop it to a `zsh -fc` that checks one sentinel symlink instead of `readlink`-ing 431; (b) `activation-watch.sh`'s 4 `for f in "$DIR"/*.sh` loops call `basename`/`grep`/`head` per file — bash parameter expansion (`${f##*/}`) removes 98 forks with no behaviour change.
Sizing: −4.0 s and −600 forks per session start; **−9,000 processes per 15-agent wave** · effort **S** · risk **low** (both are advisory/backstop, neither can block)
Existing mechanism: `config-mirror.zsh` + the launcher wrapper — **EXTEND** the launcher's guarantee, delete the per-session re-assert.

**Finding: `notify.sh` blocks the Stop chain on a synchronous AppleEvent**
Evidence: bimodal 4 ms (debounced) → **963 ms median, p95 2,650 ms** undebounced; `notify.sh:306` `nty_osa osascript -e "$_NTY_AS"` is synchronous under `timeout 5`, while `:292–296` already `&`+`disown`s `afplay`
Cost now: on a real turn (Stops are >2 s apart, so the debounce does **not** engage) this is the Stop chain's largest single member and reaches **53% of its 5 s timeout** at p95 — a timeout kill is silent
Re-architecture: background the `osascript` exactly as `afplay` already is (`&` + `disown`). The hook emits no decision, so nothing downstream depends on its completion.
Sizing: −950 ms median off every turn end · effort **XS** · risk **low**
Existing mechanism: `hooks/lib/osa.sh` `osa_bounded` — the bound stays; only the wait goes.

**Finding: `session-continue.sh` is the fleet's single most expensive hook and nothing had measured it**
Evidence: **691–1,085 ms, 38 external execs (`git`×9, `jq`×5, `mkdir`×4, `cut`×3, `shasum`×2)** on the abstain path, at every turn end; absent from `HOOK_CHAIN_COST.md` entirely
Cost now: ~⅓ of the 2.2 s Stop serial sum; 32 turns/h × 0.8 s ≈ 26 s/h fleet-wide
Re-architecture: the same **abstain-class** treatment M1–M3 applied to `curl-gate.py`/`waiting-recycle.sh`/`teammate-checkpoint.sh` — batch the 5 `jq` into one (M3's sentinel-guarded pattern), make the 9 `git` calls lazy behind the gate that already decides most invocations do nothing, and `read`-instead-of-`cat`
Sizing: precedent says **−30 to −37%** ⇒ ~−250 ms/turn · effort **M** · risk **medium** (it can `decision:"block"`, so equivalence must be mutation-proved per site)
Existing mechanism: `HOOK_CHAIN_COST.md` §4 M1/M2/M3 — **the method is proven and documented; this is the fourth application of it**, and the largest remaining target.

**Finding: `qos-rewrite.sh` has grown 2.8× and is now the #2 PreToolUse cost**
Evidence: **120 ms / 15 execs (`grep`×8)** measured today vs **43.30 ms** in `HOOK_CHAIN_COST.md` §2.3; it is not in that document's remainder table at this size
Cost now: 120 ms on every Bash call = 30% of the PreToolUse serial sum, 744/h ⇒ 89 s/h
Re-architecture: the 8 `grep` forks are pattern matches bash `[[ =~ ]]` can do natively — **but this is the same class as R-3** (`validate-bash.sh`'s 14 greps), which was deliberately deferred pending a differential corpus proving identical verdicts. Same discipline applies: corpus first.
Sizing: ~−50 ms/Bash call if taken · effort **M** (corpus is the work) · risk **medium**
Existing mechanism: **R-3, backlog `8942f3b1506d`** — widen it to cover `qos-rewrite.sh`; one corpus serves both.

---

## 7. Consolidation design — what the measurement supports (question d)

**A single dispatcher per event, reading a manifest: NOT RECOMMENDED.** Grounds, in order:

1. **It is already built and already measured negative.** `hooks/hook-chain.sh` (331 lines) +
   `config/hook-chains.d/` + `tests/hook-chain.bats` + `tests/hook-chain-live-parity.bats` landed
   **inert** in `5c88633f`: the real 6-guard PreToolUse chain went 174 ms → ~180 ms, and
   `validate-bash.sh` got **worse** under sourcing (94 → 142 ms). Building it again is
   `search-branch-graveyard-before-building`.
2. **Parallelism has already taken the win a dispatcher would take.** A serial dispatcher would turn a
   179 ms parallel burst into a 397 ms serial walk — the collapse is a **latency regression** of 2.2×
   unless the dispatcher itself re-parallelises, at which point it has re-implemented the harness.
3. **It targets the wrong term.** The registered-entry fork floor is ~5–9 ms × 13 = **~100 ms of the
   728 ms** per Bash call (14%); 86% is inside the hooks. Consolidation cannot touch the 86%.
4. **Blast radius.** One shared dependency in front of 79 entries across 12 events, in a repo whose
   standing rule is *"a hook failure must never block a tool by accident"* and whose own memory records
   `addon-failure-exceeds-its-blast-radius`.

**A per-turn fact cache (git facts computed once): NOT RECOMMENDED as designed, for a mechanical
reason.** Hooks run **in parallel**, so there is no ordering in which one member computes a fact and the
others read it — every member of a burst starts simultaneously. A cache would need its own lock and a
first-writer race, i.e. a new synchronisation primitive on the hottest path, to save `git rev-parse`
calls measured at **3 ms**. The cross-hook duplication `HOOK_CHAIN_COST.md` §2.5 counted (12 hooks
`jq`-parsing the same stdin) is real, but at 2 ms per `jq` the whole prize is ~25 ms per event, and the
parallel-race cost exceeds it.

**Matcher narrowing: no win available.** 23 of the 26 tool-call-triggered entries are already tool-scoped. The 3
match-all PostToolUse entries are each *correct* to be match-all — `teammate-checkpoint.sh` is a
crash-recovery net that must count every tool call, and both beacon/mailbox members must clear/drain
regardless of tool. Narrowing them changes semantics, not cost.

**What IS supported — targeted, per-hook, no new process model.** All six findings in §6 are
single-file changes that preserve every blocking verdict and need no ordering guarantee, because
**parallel execution means there is no order to preserve**: each hook's stdout contract
(`decision`/`systemMessage`/`additionalContext`) and its exit code are unchanged by every proposal above.

**Landing path.** Per `migrations/README.md`, anything touching `settings.json` declares
**`# migration-class: c10`** — staged, never auto-run, filing exactly one operator step via
`cc-backlog needs` with an event-keyed id. That covers **only** the two-timeout fix (§6.2), which is the
sole settings-touching item; next free number is **`migrations/0009-hook-timeout-floors.sh`**, with
`# migration-step:` naming the operator-owned settings edit and `# migration-run:` carrying the exact
command. The other five findings are **`mechanical`** — they edit hook bodies, not registration, so they
land in the ordinary diff with their tests and need no migration at all.

---

## 8. Adversarial self-pass — including one hypothesis this pass killed

**❌ REFUTED — "hooks pay 234 ms for full-table `ps` scans, which grows with fleet size."** I measured
`ps -eo pid,ppid,command` at **234 ms median / 481 ms p95** against a 1,179-entry process table, versus
**0 ms** for a targeted `ps -o comm= -p <pid>`, and was about to make superlinear feedback
(*more sessions → bigger table → slower hooks → …*) the report's headline. Then I grepped for the form
actually used: **`grep -rnE 'ps +-[a-zA-Z]*(e|A|ax)' hooks/*.sh` returns nothing.** Every `ps` in
`hooks/` is the targeted `-p` form (`live-session-registry` 4, `lead-crash-watchdog` 6,
`session-register` 4, `session-beat` 3, `teammate-auto-shutdown` 2, `session-end` 2). The full-scan cost
is real but belongs to the **pollers/daemons (axis C)**, not to the hook chain. The feedback loop does
not exist here. `session-beat.sh`'s 8 targeted `ps` calls (an ancestor walk, `:74–82`) are still 8 forks
per prompt *and* per Stop — real, but ~50 ms, not 234.

**⚠ My figures UNDERSTATE, and I bounded by how much.** Every timing used a synthetic session id and a
throwaway repo, i.e. the **abstain path**. Re-run against the real `claude-infrastructure` checkout
(**120 worktrees, 256 MB `.git`**): `validate-bash.sh` 132 → **174 ms** (+32%), `curl-gate-scope.sh`
22 → 28 (+27%), `git-worktree-guard.sh` 46 → 49 (+7%), `qos-rewrite.sh` 120 → 126 (+5%). So the real-world
figure is **+5% to +32%**, not a multiple — the extrapolations in §4 are conservative by ~15%, which does
not change any conclusion. The tail is worse than the median, though: `teammate-checkpoint.sh` p95 goes
60 ms → **656 ms** in the big repo.

**⚠ Timeout headroom is the one place this layer is genuinely fragile.** Measured p95 against configured
timeout: `activation-watch.sh` **37%** (1,861 ms / 5 s), `config-mirror-assert.sh` **36%** (2,859 / 8 s),
`session-continue.sh` **35%** (1,752 / 5 s), `notify.sh` **53%** (2,650 / 5 s). These were taken at load
40–106; the box reached **141** during the wave, and hook wall time scales ~1.5× with that swing
(`session-continue.sh` 691 ms at load 79 → 1,085 ms at load 100). At load 141+ these hooks are at or
past their caps — and a timeout kill is **silent**: the config mirror is not asserted, the activation
alarm does not print, and nothing reports either. Two of the four are SessionStart hooks, so the failure
concentrates in exactly the wave-launch burst.

**✔ Checked and clean:** no project-level settings file contributes hooks (both declare 0), so 79 is the
whole surface and CC de-duplicates cross-file handlers anyway. My exec counter self-contaminated on its
first run (its own `wc`/`sort`/`uniq` ran under the counting shim, inflating every row by ~6); rebuilt
with absolute paths and **all counts in this report are from the corrected instrument**.

**Not covered, named:** `SessionEnd`'s 7 hooks against the documented **1.5 s shared budget** — the one
event with a *shared* rather than per-hook cap, and the one I could not time without deregistering live
sessions. If any owner takes one more thing from this axis, that is it.

---

## 9. Reproduction

Harness at `/tmp/hookbench/` — `bench.sh` (interleaved A/B, `time` builtin), `execcount.sh` +
`mkshim.sh` (60-binary counting PATH shim), `b-{pre,post,prompt,stop,start}.sh` (parallel bursts),
`pay-*.json` (payloads), `repo/` (throwaway git repo). Re-run any row with
`bash /tmp/hookbench/bench.sh <n> <payload> <cwd> <label> <hook> [args]`. **Quote every figure with its
load** — and re-derive rather than quote, per this repo's `published-figure-decays` rule:
`bash-execution.log` rotated mid-investigation and invalidated the rate `HOOK_CHAIN_COST.md` §2.4
publishes.

---

## 10. Lead steer — the three P0s verified against live disk (2026-08-10)

Lead's steer confirms §2 and §7 (parallel; no dispatcher) and names three unfixed P0s. **One is
confirmed and worse than estimated; one is a misread line over a real but unreachable cost; one is
stale and already fixed.** Enforcing-store edge named per item.

### (a) `setup-task-symlinks.sh` — ✅ CONFIRMED, worse than estimated. The best finding in this axis.

**Registered:** `~/.claude/settings.json:634–638` — command at **:636**, `"timeout": 5` at **:637**.

**Root cause** — `hooks/setup-task-symlinks.sh:93–96`:
```bash
for dir in "$TASKS_DIR"/*/; do
    [ ! -d "$dir" ] && continue
    regenerate_summary "$dir"
done
```
`TASKS_DIR` resolves via `lib/task-helpers.sh:14` to `$CC_CONFIG_DIR/tasks` — which holds
**2,166 task-list directories, every one empty** (0 `*.json`, 0 B). Identical count in all four config
dirs (`.claude`, `.claude-tertiary`, `.claude-secondary`, `.claude-quaternary`). `regenerate_summary`
(`lib/task-helpers.sh`) costs **4 external execs** (`basename`, `cat`, `find`, `jq`) per dir even on an
empty one, because the empty branch still writes a `_summary.json` via `jq -n`.

**Measured, fully isolated** (real hook, `CC_TASKS_DIR` seam → 200-dir scratch fixture, cwd = scratch
repo, load 67):

| | value |
|---|---|
| 200-dir fixture | **7,036 ms**, p95 8,315 ms · **1,218 external execs** (`jq`×405, `basename`×401, `find`×203, `cat`×200) |
| per dir | ~35 ms · ~6.1 execs |
| **extrapolated to the real 2,166 dirs** | **~76 s · ~13,200 execs** |
| configured timeout | **5 s** |
| ⇒ | **SIGKILLed at 5 s having processed ~6.5% (~140 of 2,166 dirs)**, after ~865 execs |

**Self-evidencing proof it has never completed — no inference required.** In
`claude-infrastructure/.claude-tasks/`, the artifact written **before** the loop (`_all`, `:22–26`) is
dated **Aug 10 01:03 — today**. Every artifact written **after** the loop (`_current`,
`.active-list-id`, `:106–118`) is dated **Jul 30 21:32 — 11 days stale**. The hook has not reached its
own tail since 2026-07-30. Worse, the frozen `_current` points into `~/.claude/tasks/` while today's
`_all` points into `~/.claude-tertiary/tasks/` — it is stale *and* aimed at the wrong account's store,
which is precisely the account-2/3/4 mis-target `task-helpers.sh:12–15` exists to prevent.

**Cost:** ~170 SessionStarts/day × 5 s = **14 min/day of CPU** and **~147,000 forks/day** for zero
delivered output; a 15-agent wave burns **75 s and ~13,000 forks** at launch, concentrated at the
moment the box is most loaded.

**Removal edge — and why removal is the *second* choice.** Deleting the 5-line object at
`settings.json:634–638` is a **`c10`** migration (touches `settings.json`) and would also drop `_all`,
the one artifact the hook still delivers. The better fix needs **no settings edit at all**: bound the
loop to the lists actually consumed — the active list plus this session's own `TASK_LIST_ID` — instead
of all 2,166. That is a hook-body change ⇒ **`mechanical`**, lands in the ordinary diff, drops the cost
to ~2 dirs (~70 ms), and *restores* the 11-days-dead tail. Pair it with a GC of the 2,166 empty dirs
(store side — axis I owns that; this hook is merely its largest consumer), because the loop is O(N)
unbounded either way.
**Sizing:** −5 s and −865 forks per SessionStart · effort **S** · risk **low** (the loop's output for
empty dirs is a constant-shaped `_summary.json` nothing reads).

### (b) `cc-backlog list --blocked` on the Stop path — ⚠ line is a misread; cost is real but I could not reach it

**`operator-readout.sh:702` does not invoke anything.** It is a string assignment inside a `case`:
```bash
backlog)  cn="$c_backlog";  rcmd='cc-backlog list --blocked'; clabel="blocked backlog" ;;
```
`rcmd` is the command *printed for the operator to paste*. Same at `:650`, `:749`, `:805`. The real
execution site is the binary resolution at `:370–372` inside `render_block`.

**The 3.4 s is real in origin and the fix already landed.** The file's own comment at `:906–914` sizes
it: *"render_block costs ~2711 ms (73% of the 3688 ms Stop chain) — 24 command substitutions, ~100
forks, git x7 / jq x6 / cc-backlog x5"*. Directly beneath it, `cheap_stamp()` (`:928+`, row 13 M3 /
`MACHINE_CAPACITY_V2.md` §8.5.3) gates the render on `stat`s plus two bounded `git` reads — *"measured
~60-100 ms vs 2711 ms"* — with kill switch `CC_READOUT_DAMP=off`.

**What I measured, and the limit of it.** operator-readout = **183 ms** (p95 220) default,
**182 ms** with `CC_READOUT_DAMP=off`, **202 ms** with `CC_OPREADOUT_NOW=1` — **10–11 execs in all
three arms, identical**. Three arms that should differ and do not means one thing: a synthetic session
id abstains **upstream of `render_block`** every time. **My instrument cannot reach the subject, so I
neither confirm nor refute the 3.4 s.** Recording that as a limit rather than a result, because an
abstain-path number presented as a render-path number is exactly the false-negative this repo's
`unfixtured-sensor` and `positive-control-the-denominator` scars are about.

**What I can state as measured fact — and it is worse than the claim.**
`cc-backlog list --blocked` **on its own** costs **5,227 ms median, p95 6,706 ms** (n=9, load 84),
against `~/.claude/autonomy/backlog.jsonl` at **7,097 rows / 2.0 MB** (`bin/cc-backlog:467`).
`render_block` calls it **×5**. So whenever the damp does *not* suppress, a **single** one of those five
calls exceeds half the hook's **10 s timeout** at p95 — and a timeout kill here is silent, leaving the
operator's close block unrendered with nothing reporting why.

**Spec.** Two independent changes, neither touching `settings.json` ⇒ both **`mechanical`**:
1. **Memoize the query per invocation.** All five sites want one answer. Use M2's parent-fills-memo
   pattern (`HOOK_CHAIN_COST.md` §4 M2): a `$( )` runs in a subshell so a self-populating memo can
   never hit — the parent must fill it once before the first substitution and the sites only read.
   Saves 4 × 5.2 s on the render path.
2. **Give `cc-backlog` a bounded read path.** 5.2 s for one query is a **full-store scan** of a
   7,097-row JSONL. `--blocked` needs a filtered tail, not the whole file. The store's growth is axis
   I's; the per-fire read bill is mine, and this is the largest single read in the hook layer.

### (c) `curl-gate.py` 46 ms / 26% — ❌ STALE. Already fixed 3 days ago. Close it.

| claim | live truth |
|---|---|
| `curl-gate.py` registered on every Bash call | **No.** `settings.json:435` registers **`curl-gate-scope.sh`**. `curl-gate.py` appears **nowhere** in live settings.json. |
| 46 ms, 26% of the chain | **22 ms, 2 execs = 5.5%** of the 397 ms chain (§3.1) |
| source: `hook-chain.sh:49–51` | a **comment inside an unregistered file** — `grep -n hook-chain settings.json` returns nothing |

Migration **`migrations/0002-curl-gate-scope-registration.sh`** landed **2026-08-07**.
`config/hook-chains.d/pretooluse-bash:13` still literally reads `curl-gate.py`, and its own header
`:6–11` says it is left that way **deliberately**, mirroring what settings.json registered at the time.

**This is R-6 firing exactly as written.** `HOOK_CHAIN_COST.md` §5 R-6 predicted it in advance: *"the
registry names `curl-gate.py` because that is what settings.json registers today. If the operator runs
`26-curl-gate-scope-activate.sh`, settings.json will name `curl-gate-scope.sh` and **the two sets
diverge**… whoever wires the dispatcher must reconcile them."* The activation ran; the registry did not
follow; and R-6 was filed as harmless *"no runtime effect while the dispatcher is inert"*. It has now
had a **cost that is not runtime**: it misinformed this wave into spending a P0 slot on solved work.

**The residual action is not a narrowing — it is R-6's reconcile**, and it is now worth doing for a
reason R-6 did not anticipate. Either update `config/hook-chains.d/pretooluse-bash:13` to
`curl-gate-scope.sh`, or **delete the inert dispatcher set entirely** (`hooks/hook-chain.sh`,
`config/hook-chains.d/`, its two /Users/chrisren/.claude/bin/cc-bats suites) — §7 establishes it will never be wired, and an inert
artifact that misleads readers is worse than no artifact. Neither touches `settings.json` ⇒
**`mechanical`**. Generalisable form of this incident, worth a memory line: *an inert mechanism's stale
copy of live config is a documentation hazard even when it has no runtime effect.*

### Today vs `HOOK_CHAIN_COST.md`, per member

| member | that doc (load 16) | **today** (load 40–106) | note |
|---|---|---|---|
| `curl-gate.py` → **`curl-gate-scope.sh`** | 35.41 | **22** (2 execs) | M1 shipped + registered; claim (c) is stale |
| `validate-bash.sh` | 70.26 | **132** scratch / **174** real repo | 23 execs, 14 `grep` — R-3 still open |
| `qos-rewrite.sh` | 43.30 | **120** (15 execs, 8 `grep`) | **2.8× growth**, not in any remainder table — new |
| `git-worktree-guard.sh` | 20.46 | **46** | |
| `keychain-guard.sh` | 15.30 | **34** | ⚠ no timeout → 600 s default |
| `rm-safe-allowlist.sh` | 14.22 | **21** | |
| `ship-rail-push-allow.sh` | 13.50 | **22** | |
| **PreToolUse/Bash total** | **212.44** | **397 serial / 179 parallel burst** | |
| `waiting-recycle.sh` | 96.55 → 67.46 post-M2 | **127** | ⚠ no timeout → 600 s default |
| `teammate-checkpoint.sh` | 51.57 → post-M3 | **36** (8 execs) | M3 holding — 9→8 execs |
| `log-bash.sh` | 29.07 | **46** | |
| `cc-permission-beacon.sh` | 14.76 | **30** | |

Fleet rate has also moved: **744 Bash/h** over a 9.41 h window vs that doc's **480/h** over 39 h — and
its source rotated at **2026-08-09T22:21Z**, so §2.4's window no longer exists. Re-derive, never quote
(`published-figure-decays`).
