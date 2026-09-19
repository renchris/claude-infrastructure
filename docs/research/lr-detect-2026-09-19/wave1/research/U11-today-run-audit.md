# U11 — audit of today's /limit-recover run (2026-09-19, America/Chicago)

Sources: lead transcript `/Users/chrisren/.claude-tertiary/projects/-Users-chrisren-Development-claude-infrastructure/11569d45-8a26-4bf0-a568-51efd70eff63.jsonl` (1,093 records, 151 tool calls, 12:01:27→13:54); `~/.reso/limit-recover/fleet/one-20260919T17*/`; `/var/folders/.../handoff-recycle-<pane>-*.log`; the five target-store transcripts. All clock times America/Chicago. Working files: `.../scratchpad/lr/{calls.json,timeline.txt,pairs.py,detail.py}`.

---

## 0. The headline the brief did not have

Two independent facts, both measured, both bigger than any latency number:

**(A) The ingest — the entire point of `/limit-recover` — never ran on 2 of 5 sessions, and nothing said so.**
`grep`'d the two target transcripts for `bundle-2026`: **0 records** in `d02d8feb` (pane 112) and **0** in `e442434c` (pane 121), from transplant to now. Their generated launchers *did* carry it (`lr-launch-d02d8feb-oucN3k.sh` → `--prompt /limit-recover\ ingest\ …bundle-20260919T171945Z`), but it was never submitted. Pane 112's run is the one recorded as **`recycle-in-place/RECOVERED`** (`one-20260919T171910Z/results.tsv`) — the only clean verdict of the day. The salvage audit it certifies did not happen.

**(B) The engagement oracle passes on the harness's own resume boilerplate.**
`scripts/handoff-fire.sh:6848` prints `→ relaunched + ENGAGEMENT CONFIRMED in $RSID (a real assistant turn, not just a process)`. What satisfied it on pane 112 at 12:20:49 was:

```
12:20:49 user  META  text:Continue from where you left off.
12:20:49 assistant     text:No response requested.
```

A synthetic meta-user record and a six-word no-op. Same shape on pane 121 at 12:47:15. So `RECOVERED` is provable from disk to mean *"a claude process exists and the resume banner turned over"* — not *"the recovery prompt was accepted"*. `lr-fleet` then writes `RECOVERED` into `results.tsv` and the run looks green.

Ingest delivery, per session: **auto-submitted 1/5** (cb227486 p117, 12:57:29), **hand-repaired 2/5** (09e64dcb p111 12:43:23; 28f07827 p114 12:58:24), **never delivered 2/5** (d02d8feb p112, e442434c p121).

---

## 1. Wall clock and turn structure

Turn boundaries are the `queue-operation` `dequeue` records — the only un-fakeable turn edges in the transcript.

| Turn | Span | Min | What filled it |
|---|---|---|---|
| T1 | 12:01:33 → 12:16:01 | 14.5 | census 54.8 s · `--json` 56.4 s · dry-run 68.0 s · ranker 2.5 s · **first fire, 605 s foreground then backgrounded** |
| T2 | 12:16:01 → 12:57:08 | **41.1** | capacity research · 4 fires · 5 blocking result-polls · pane-111 ingest fight (17 min) · manual repairs of 121/114/117 · 3 censuses |
| T3 | 12:57:08 → 12:59:41 | 2.6 | screenshot #4 (stale) · census · 114 ingest by hand |
| T4 | 12:59:41 → 13:01:07 | 1.4 | screenshot #5 (stale) · fixpoint census |
| T5 | 13:01:07 → ~13:38 | ~37 | Stop-hook block → research that refuted the lead's own packet · commit on `main` in the shared checkout · 7.7-min permission prompt · branch+ship-land · 12.5 min polling the land |

Tool-call time: **4,134.0 s = 68.9 min** over 151 calls (68.9 / 98.7 wall = 70%).

Buckets (my classifier, `pairs.py` + inline):

| bucket | n | sec | min |
|---|---|---|---|
| wait/poll (blocking `until` loops) | 17 | 2330.0 | **38.8** |
| fleet / handoff / ship invocations | 18 | 696.5 | 11.6 |
| git | 6 | 484.5 | 8.1 |
| census / quota | 14 | 351.2 | 5.9 |
| pane I/O (kitty / it2 / cc-pane) | 32 | 175.4 | 2.9 |
| other | 64 | 96.5 | 1.6 |

**38.8 of 68.9 tool-minutes (56%) were the lead watching a file.**

Token cost of the lead to 13:38:41: 344 assistant messages, **269,724 output · 1,101,781 cache-creation · 88,968,838 cache-read · 688 input**. Cache-read dominates by 80×; it scales with *turn count at a ~365 K context*, not with per-turn size. The token lever is **fewer lead turns**, not shorter commands.

---

## 2. The operator's actual complaint, measured exactly

Screenshots are queued prompts. They dequeue only at a turn boundary. From the `queue-operation` records:

| prompt | enqueued | dequeued | **queued** |
|---|---|---|---|
| `/limit-recover [Image #2] [Image #3]` | **12:02:30** | 12:16:01 | **13 min 31 s** |
| `/limit-recover [Image #4]` | **12:19:00** | 12:57:08 | **38 min 08 s** |
| `/limit-recover [Image #5]` | **12:24:28** | 12:59:41 | **35 min 13 s** |

**Cumulative operator-prompt latency: 86 min 52 s.** #4 and #5 were both already resolved by the census path before they were read (T3/T4 are the lead discovering they were stale).

The cause is entirely inside the lead's control: **every fired recovery already posts a `task-notification` `enqueue` the moment it finishes, and the lead's blocking poll exited 1–5 s after that enqueue in every single case.**

| run | notification enqueued | lead's poll exited | poll duration wasted |
|---|---|---|---|
| biffuq879 (112) | 12:21:05 | 12:21:07 | 75.6 s + 36.4 s |
| bfgk93iv2 (111) | 12:23:54 | 12:23:56 | 144.9 s |
| bpjhefw6c (121) | 12:46:35 | 12:46:36 | 145.0 s |
| brfl05yff (114) | 12:51:26 | 12:51:27 | 154.1 s |
| bvz9yrb1n (117) | 12:54:45 | 12:54:46 | 157.0 s |
| bp08nrj1o (ship) | 13:23:14 | 13:23:19 | 362.0 s + 391.4 s |

**1,466 s = 24.4 min of polling bought zero information.** Had the lead ended its turn after each fire, the notification would have woken it at the same instant *and* the operator's queued screenshots would have dequeued first. This single behaviour change removes ~87 min of operator-visible latency and ~24 min of lead turn-time at once.

---

## 3. Per-session ledger

Times are Chicago. "Proven engaged" = first `assistant` record in the **target** store after the transplant. "Ingest in" = first record carrying `limit-recover ingest`.

### d02d8feb — pane 112 — next4 → next2 — Fable 5.1/xhigh — cwd `wt-cc-095358-75429`
| t | event |
|---|---|
| 12:01:46 | census: `d02d8feb next4 112 70909 claude-fable-5-1/xhigh RECOVERABLE limit 3m` |
| 12:04:45 | attempt 1 `lr-fleet --one … --target next2 --source-pane 112` (foreground) |
| 12:15:48 | **PARKED / capacity** (`one-20260919T170450Z/results.tsv`), after 600 s foreground + ~60 s background = **11.1 min** |
| 12:17:03 | attempt 2, `CC_ADMIT_LOAD_TERM=off` — produced `one-20260919T171706Z/results.tsv` **0 bytes**; lead `TaskStop`'d it 12:18:53 (**1.8 min**) |
| 12:19:07 | attempt 3, `CC_ADMIT_LOAD_TERM=off CC_SP_ACTIVE_OVERRIDE=4` |
| 12:19:45 | transplant ok → `~/.claude-secondary/projects/-Users-chrisren-Development--worktrees-wt-cc-095358-75429/` |
| 12:20:49 | **"proven engaged" = `Continue from where you left off.` / `No response requested.`** (+64 s) |
| 12:21:05 | `recycle-in-place/RECOVERED` |
| — | **ingest NEVER delivered** (0 records matching `bundle-2026`) |

Total 16.3 min. Only session whose watcher relaunch survived — `handoff-recycle-112-1789838387-8495Kv.log` shows the same `⚠ no claude … 45s after relaunch — retyping once` as the four failures, then succeeded on the retype.

### 09e64dcb — pane 111 — next4 → next3 — Opus 5/high — cwd `claude-infrastructure`
| t | event |
|---|---|
| 12:21:23 | fire (`CC_ADMIT_LOAD_TERM=off CC_SP_ACTIVE_OVERRIDE=6`) |
| 12:22:03 | transplant ok → `~/.claude-tertiary/.../09e64dcb…jsonl` |
| 12:23:54 | **`recycle-in-place/PARTIAL`** — `!! relaunch typed but no claude process appeared within 90s` |
| 12:24:42–12:25:29 | 6 calls, 18 s, discovering `it2` subcommands |
| 12:26:17 | `it2 session run -s 111 "bash …lr-launch-09e64dcb-6SGtgQ.sh"` → rc 0 |
| 12:26:26 | **proven engaged** (+4 m 23 s from transplant) |
| 12:26:38→12:32:40 | blocking poll **361.5 s**, no ingest |
| 12:34:24 | `cc-pane send 111 "<ingest>"` **16.7 s, rc 0, but nothing submitted** — `cc-type-verified: could not disarm zsh spell-correction in pane 111 — proceeding (the command line is still echo-verified)` |
| 12:34:50→12:38:51 | blocking poll **241.3 s** |
| 12:39:23 | `it2 session send -s 111 $'\r'` ×2, rc 0 — no effect |
| 12:39:39→12:42:40 | blocking poll **181.1 s** |
| 12:43:08 | `kitty @ --to unix:/tmp/kitty-73832 send-text --match id:111 "<ingest>"` |
| 12:43:18 | `… send-text --match id:111 $'\r'` → **works** |
| **12:43:23** | **ingest in** — 21 min 20 s after transplant |

Manual repair cost **17.1 min**, of which 13.1 min is three blocking polls of a prompt that had never been submitted.

### e442434c — pane 121 — next4 → next3 — Fable 5.1/xhigh — cwd `claude-infrastructure`
| t | event |
|---|---|
| 12:43:59 | fire |
| 12:44:39 | transplant ok |
| 12:46:35 | **PARTIAL**, same `no claude process appeared within 90s` |
| 12:46:47 | **the culprit, read verbatim off pane 121:** `t3 — load 25.15 on 10 cores = 2.51/core > ceiling 2.0/core (refusal 2 of 3; once the budget is spent the next evaluation ADMITS and pages)` / `Override for one resume: CC_ADMIT_GATE=off ; raise the bar: CC_ADMIT_MAX_LOAD_PER_CORE=<n>` |
| 12:47:01 | lead retypes `CC_ADMIT_LOAD_TERM=off nocorrect bash …lr-launch-e442434c-Ljfskl.sh` |
| 12:47:09 | `$'\r'` → up |
| 12:47:15 | **proven engaged** (+2 m 37 s) — again `Continue from where you left off.` / `No response requested.` |
| 12:47:24–12:47:49 | 17.9 s fighting composer residue: `$'\x15'` echoed as `^U`; `send-key ctrl+u` rendered as the literal `^[[117;5u`; 45× `backspace` left `^R[117;5u` |
| — | **ingest NEVER delivered** |

### 28f07827 — pane 114 — next4 → next2 — Fable 5.1/xhigh — cwd `wt-cc-100046-36511`
12:48:48 fire · 12:49:36 transplant · 12:51:26 **PARTIAL** (`⚠ recycle proceeding with 1 IN-FLIGHT subagent(s) — … they are being KILLED deliberately`) · 12:51:31 lead retypes with `CC_ADMIT_LOAD_TERM=off` · 12:51:39 `\r` · **12:51:44 proven engaged** (+2 m 09 s) · 12:58:05 `ESC` to clear composer · 12:58:15 ingest typed · 12:58:22 `\r` · **12:58:24 ingest in** (+8 m 48 s).

### cb227486 — pane 117 — next4 → next2 — Fable 5.1/xhigh — cwd `claude-infrastructure`
12:52:05 fire · 12:52:54 transplant · 12:54:45 **PARTIAL** · 12:54:49 lead retypes with `CC_ADMIT_LOAD_TERM=off` · 12:54:56 `\r` · **12:55:02 proven engaged** (+2 m 08 s) · **12:57:29 ingest in** — the *only* auto-submitted ingest of the day (+4 m 35 s).

---

## 4. Root cause of the 4 PARTIALs — settled, with the pane text as the receipt

The watcher does everything right. `handoff-recycle-{111,114,117,121}-*.log` all read:

```
→ pane N CONFIRMED at a shell prompt after 3–6s — typing relaunch
→ relaunch typed into N: cd <cwd> && nocorrect bash /var/folders/.../lr-launch-<sid>-XXXX.sh
⚠ no claude on /dev/ttysNNN 45s after relaunch — retyping once
!! relaunch typed but no claude process appeared within 90s — fallback comment typed into pane
```

The typed command **ran**, and `lr-fire-resume.sh` **refused itself**:

- `scripts/limit-recover/lr-fire-resume.sh:324` — `if ! cc_capacity_admit lr-fire-resume "resume $SID on $ACCT"; then … exit 9`
- `scripts/lib/capacity-admit.sh:161` `CC_HW_DEFAULT_MAX_LOAD_PER_CORE=2.0`; `:581` `budget="${CC_ADMIT_BUDGET:-3}"`
- observed at 12:46:47 on pane 121: **2.51/core > 2.0, refusal 2 of 3**

The load was manufactured by a **background-QoS** sibling, i.e. by design non-contending:

```
12:16  up 2 days, 19:48, 5 users, load averages: 32.92 43.96 69.92      (10 cores ⇒ 3.29/core)
80016  46:09 /opt/homebrew/bin/timeout -k 10 10800 nice -n 19 /usr/sbin/taskpolicy -c background bats tests/…
bats workers: 10
```

The repo already knows this term is the wrong input and already disables it on its other high-volume spawn surface — `hooks/agent-teams-enforce.sh:229` `CC_ADMIT_LOAD_TERM=off CC_ADMIT_SID=… cc_capacity_admit agent-tool …`, and `scripts/handoff-fire.sh:6069` comments *"The Agent tool's gate has run `CC_ADMIT_LOAD_TERM=off` since Wave D"*. `lr-fire-resume.sh` does not.

**Why `CC_ADMIT_LOAD_TERM=off` on the lead's `lr-fleet` invocation did not help:** it is set in the *lead's* Bash environment. The relaunch is a string typed into the **pane's own zsh**, which inherits nothing from the lead. The generated launcher already `export`s two variables (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`, `CLAUDE_CODE_TASK_LIST_ID`) — the override belongs there, in the file, not in the caller's env.

**Why pane 112 survived:** same log shape, same retype, but its relaunch landed inside the 3-refusal budget window (`capacity-admit.sh:581`, `:287`: *"once the budget is spent the next evaluation ADMITS and pages"*). Luck, not difference in kind.

---

## 5. The 7.7-minute `git branch + git reset --hard` — it was a permission prompt, not 219 worktrees

`toolu_01MWzMjR7zpRSqswiK9rryZ9`, issued 13:02:19, result 13:10:01 = **461.6 s**. Its PreToolUse attachment, timestamped 13:02:19, is the **only `"ask"` in the entire session**:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask",
 "permissionDecisionReason":"git reset --hard can destroy uncommitted work. Verify intentional."}}
```

Source: `hooks/validate-bash.sh:1665-1667`. The 461.6 s is human answer latency, wall-to-wall.

Refuting the worktree hypothesis with the neighbours: `git status --porcelain | head -10` at 13:02:16 took **0.3 s**; `git branch --show-current; git log --oneline origin/main..main; git rev-list --count` at 13:02:09 took **0.3 s**; `git worktree add …` at 13:10:26 (the call that printed `219`) took **2.9 s**. Index/worktree cost is ~0.3 s here; hooks add ~0.2 s.

The upstream defect is that the call existed at all: the lead wrote `docs/research/limit-recover-capacity-park-2026-09-19.md` and committed it on `main` **in the shared checkout**, which `.claude/CLAUDE.md` § *Never commit or land in the shared checkout* forbids, then had to unwind it.

Related, and also mis-attributed in the brief: **ship-land was not blocked on lock contention.** Its own output reads `→ land-lock: acquired (no wait) — machine-wide landing lock held.` The 12.5 min was the whole-tree gate suite (`bats-testname-eval-lint … 697 suite(s) scanned`, loaded-untracked ratchet, offbox-admission-lint, selftest memo) running against a **docs-only, one-path diff** that the gate itself classified `lint-only land` / `0 direct suite(s) map to this range`.

---

## 6. Identification from a screenshot — why it is structurally ambiguous today

What the statusline renders (`~/.claude/statusline.sh`, real file, 486 lines):
`GLYPH_PREFIX` = `(N)` account index (`:426-431`) · `PCT_SEG` = context % (`:473-477`) · `OUTPUT` = cwd basename + dirty (`:284-286`) + ` (COMMIT)` (`:290`) + branch (`:294`) + ` · EFFORT` (`:306`). Final line `:486`.
**No session id. No pane id.** Today's example, `(4) 52% · wt-cc-095358-75429 (06ce6fee5) · xhigh`.

`cwd` basename is not a key: of the 27 live rows in `~/.claude/cc-registry/`, **8 are `claude-infrastructure`** and **3 are `wt-cc-095358-75429`**.

But the index the tool needs already exists and is free to read — `~/.claude/cc-registry/<paneId>.json`, one JSON per live pane, **one directory shared by all four accounts**:

```json
{"paneUUID":"112","name":"…","cwd":"/Users/chrisren/Development/.worktrees/wt-cc-095358-75429",
 "account":"claude-secondary","pid":52095,"startedAt":1789838…,"session_id":"d02d8feb-…","surface":"pane",
 "lstart":"Sat Sep 19 …"}
```

31 files, read in milliseconds — against `lr-fleet --locate` at **54.8 / 45.0 / 41.1 / 37.4 / 36.2 / 38.6 s** (6 runs, 253.1 s = 4.2 min today). `/tmp/cc-telemetry/<sid>.json` (statusline `:148-157`) is a second, per-render index carrying `session_id`, `cwd`, `pid`, `cfg`.

Two cheap closures:
1. Render the pane id in the statusline. `KITTY_WINDOW_ID` is already in scope there (referenced `:416`); a leading `p112·` makes a screenshot a primary key with zero lookup.
2. Until then, key the screenshot on the tuple `(account-index, cwd-basename, git-sha, effort)` against `cc-registry` + `session-window.jsonl` — the sha discriminated all three `claude-infrastructure` panes today (`bd016b0a0` / `f090d34d6` / `68691feb5`, read at 12:57:16).

The "You've hit your session limit · resets 2:40pm (America/Chicago)" line the harness prints (read verbatim off pane 114 at 12:58:31) carries **no** session id either.

---

## 7. TOP 8 avoidable delays, ranked by minutes lost

| # | Delay | Min | Root cause (cited) | The one change |
|---|---|---|---|---|
| 1 | **Operator screenshots queued behind the lead's own turns** | **86.9** operator-visible (24.4 of lead turn-time) | Every fired recovery's `task-notification` `enqueue` beat the lead's blocking `until` poll by 1–5 s, six times (§2). A queued prompt dequeues only at a turn boundary; T2 ran 41.1 min. | **Fire and END THE TURN.** `/limit-recover` must never contain a foreground wait. Let `task-notification` wake the session; the operator's prompt then dequeues first. |
| 2 | **First fire parked on capacity** | **11.1** | `lf_capacity_wait` (`lr-fleet.sh:282-291`, `LR_FLEET_CAP_WAIT_S=600`) polling a loadavg term whose input was a `taskpolicy -c background` bats run — load 32.92/10 = 3.29/core vs ceiling 2.0 (`capacity-admit.sh:161`). | Run the limit-recovery path with `CC_ADMIT_LOAD_TERM=off`, as `hooks/agent-teams-enforce.sh:229` already does; keep headroom+segments+active. |
| 3 | **Pane-111 ingest submission** | **17.1** (13.1 of it blocking polls) | `--prompt` never submitted; `cc-pane send` returned **rc 0** while delivering nothing (`cc-type-verified: could not disarm zsh spell-correction in pane 111 — proceeding`); `it2 session send -s 111 $'\r'` ×2 rc 0, no effect; only `kitty @ --to unix:/tmp/kitty-73832 send-text` + `$'\r'` worked. | One pane-write primitive (`kitty @ … send-text` over the socket), and a submit **verifier that reads the target transcript for the prompt**, not the sender's rc. `cc-pane send` must fail closed. |
| 4 | **Blocking poll on ship-land** | **12.5** | Two foreground `until` loops (362.0 s + 391.4 s); notification at 13:23:14, poll exited 13:23:19. Land-lock `acquired (no wait)` — the time was the whole-tree gate on a 1-path docs diff (`lint-only land`, `0 direct suite(s)`). | Same as #1 (end the turn), plus a docs-only fast path in `ship-land`. |
| 5 | **4 × PARTIAL relaunch + hand repair** | **~10** (4 × ~2.5 min PARTIAL window + 3 retype/clear cycles) | The relaunch runs in the **pane's** shell, where `lr-fire-resume.sh:324` re-evaluates the load term; pane 121 printed `2.51/core > ceiling 2.0/core (refusal 2 of 3)`. The lead's env override could not reach it. | Write `export CC_ADMIT_LOAD_TERM=off` **into the generated `lr-launch-*.sh`** (it already exports 2 vars), so the launcher can never be refused by the term the repo has already retired elsewhere. |
| 6 | **`git reset --hard` permission prompt** | **7.7** | Only `"ask"` of the session — `hooks/validate-bash.sh:1667`. Needed only because the lead committed on `main` in the shared checkout, against `.claude/CLAUDE.md`. | Recovery tooling must write its notes **outside** the repo (or in a worktree from the start); never emit an `ask`-class command on an autonomous path. |
| 7 | **6 full-fleet censuses** | **4.2** | `lr-fleet --locate` at 36–55 s each, re-run for fixpoint. | Read `~/.claude/cc-registry/*.json` (31 files, ms) for pane↔sid↔account↔cwd, and reserve the full scan for a `--deep` verb. Cache the last scan with a `--since`. |
| 8 | **The zero-byte run `one-20260919T171706Z`** | **1.8** + investigation | With the load term off, the ACTIVE term became binding and `cc_sp_active` returned **unmeasurable** (`active sessions mid-turn: ?`, 12:16:47), so the fire produced nothing and the lead `TaskStop`'d it; it then needed `CC_SP_ACTIVE_OVERRIDE=4`. | The capacity probe must print **which term refused and its value** on the tool's own stdout, and an unmeasurable term must ADMIT-and-say-so rather than stall. |

Not time, but worse — the two correctness defects of §0: **ingest silently skipped 2/5**, and **`ENGAGEMENT CONFIRMED` satisfied by `No response requested.`**. Any latency rebuild that keeps the current oracle will produce fast, green, empty recoveries.

Minor, uncosted: the router near-tie. At 12:03:03 `lf_pick_target` (`lr-fleet.sh:294-309`) chose **`next`** (weekly **98%**) for a Fable session; at 12:04:22 `claude-accounts --rank fable` read `next3 0.000071 / next 0.000069 / next2 0.000019` — a **3% gap** between an 11%-weekly account and a 98%-weekly one. The awk pick itself is correct (header lines go to stderr; re-ran today: `claude-accounts --rank fable 2>/dev/null | awk -v s=next4 '$1!=s{print $1;exit}'` → `next3`). The defect is the **scoring**, not the parse: weekly exhaustion is nearly unpriced in the fable lane. Also `lr-fleet --locate` labelled two recovered sessions `DUPLICATE` by counting the `cc-close-attrib` wrapper as a second process, while `--duplicates` reported none (12:55:54, 6.7 s).

---

## 8. What a 100th-percentile path looks like, given only what is measured above

1. **Identify (target ≤2 s).** `cc-registry` lookup keyed on the screenshot tuple, or directly on a pane id the statusline should print. No `--locate`.
2. **Fire once, non-blocking.** One command, `CC_ADMIT_LOAD_TERM=off` baked into both the fleet call and the generated launcher. Returns immediately with a run id; the lead's turn ends.
3. **The tool owns verification, out of band.** A detached verifier that (a) waits for a claude pid on the pane's tty, (b) waits for the **ingest prompt string** to appear in the *target* transcript — not for any assistant turn — and (c) on failure re-types through the one proven primitive and re-checks. Its verdict is a written row, not a log line.
4. **Failure is a named row, never a husk.** Today's `PARTIAL` rows were correct and complete in `results.tsv` — and nothing consumed them. The gap is a consumer, not a detector.
5. **Wake, don't poll.** The `task-notification` path already works to the second; the lead must simply stop pre-empting it.
