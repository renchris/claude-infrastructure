# B6 — The units that consume neither ceiling: Codex CLI and Pi·Codex

**Date:** 2026-08-19 · **Axis owner:** B6 · **Method:** live probes on this box, read-only on the
Claude fleet. Every number below carries the command that produced it.
**Parent:** `docs/research/orchestration-units-2026-08-19.md` (commit `4a3bd3373`, branch
`docs/orchestration-units`) § L4, which named these two backends `✅ routable` and said "no axis in
this wave owns them." This is that axis.

---

## 1 · VERDICT

**A distraction as a capacity lane, and a genuine free win as a burst tool — because "2 of 2
routable" is ONE subscription, and that subscription sustains 0.054 working units against the Claude
fleet's 9.4.** The two backends carry a byte-identical `chatgpt_account_id`, so they are two harnesses
on one meter, not two lanes. That meter is weekly, has no overage credits, and I measured it burn at
**10.8 percentage points per agent-hour** across three independent runs — which prices the whole
ChatGPT Plus plan at **9.1 agent-hours per week**, i.e. **+0.6% of this fleet's sustained capacity**.
The box would happily run 15 of them concurrently; the subscription pays for **36 minutes** of that.

Quality is *not* the reason to say no — measured today, its citations landed exactly on target in a
261-line file and 3 of 4 independent runs converged on the same two real defects. Wiring it up costs
about a day and returns half a percent. **Buy nothing, integrate nothing standing. Keep it for
hand-fired bursts where the Claude meter is the thing you are protecting.**

---

## 2 · NUMBERS

### 2.1 What is installed and routable, right now

`claude-accounts --agents` — reproduced verbatim (the renderer that prints `routable`):

```
**Agent backends beyond Claude** — registry `~/.claude/providers.json`

| backend | routable | version | auth | plan | bills outside it? | model pinned |
|---|---|---|---|---|---|---|
| Codex CLI | ✅ | codex-cli 0.147.0 | ok | ChatGPT Plus | no | gpt-5.6-sol @ xhigh ✓proven |
| Pi · Codex backend | ✅ | 0.84.1 | ok | ChatGPT Plus | no | gpt-5.6-sol ✓proven |
| Pi · Claude backend | ⊘ skipped | 0.84.1 | credentials_not_configured | Claude Pro/Max (auth works, usage does NOT draw on the plan) | 🚨 **YES** | — |
| Antigravity | ⊘ skipped | 1.107.0 | ok | UNKNOWN | UNKNOWN | — |
| Gemini CLI | ⊘ skipped | 0.29.5 | ok | UNKNOWN | UNKNOWN | gemini-3-pro-preview ⚠unproven |
| Grok CLI | ⊘ skipped | not installed | — | UNKNOWN | 🚨 **YES** | — |
- ⊘ `pi-claude` — COST GATE FAIL — bills per token outside the Max plan
- ⊘ `antigravity` — NOT AN AGENT BACKEND — the binary is the VS Code editor launcher, no non-interactive mode
- ⊘ `gemini` — DEFERRED — plan tier UNKNOWN, so the cost gate cannot clear it
- ⊘ `grok` — COST GATE FAIL — API-key-only, and we hold no xAI plan

➤ non-Claude backends ready now: **2 of 2 routable** (6 known)
- 🚨 rows marked **YES** bill OUTSIDE a plan we hold — not wired, by policy (`accounts.json spend.usage_credits_authorized=false`)
```

| # | Fact | Value | Label | Command |
|---|---|---|---|---|
| 1 | Codex CLI live and answering **today** | `PROBE-OK-B6`, rc 0, 4.39 s | **MEASURED** | `codex exec --sandbox read-only --skip-git-repo-check "Reply with exactly: PROBE-OK-B6…"` |
| 2 | Plan behind it | `chatgpt_plan_type: "plus"`, account `cc75bc9d-…fdad8a` | **MEASURED** | base64-decode `tokens.id_token` in `~/.codex/auth.json`, claim `https://api.openai.com/auth` |
| 3 | **Pi rides the SAME subscription** | `~/.pi/agent/auth.json` → `openai-codex.accountId` = `cc75bc9d-ebba-4a13-bff9-e9c083dfad8a` — **byte-identical** to Codex CLI's `chatgpt_account_id` | **MEASURED** | decode both stores and compare |
| 4 | Pinned model | `gpt-5.6-sol`, `model_reasoning_effort = "xhigh"` | **MEASURED** | `cat ~/.codex/config.toml`; header of every `codex exec` echoes `model: gpt-5.6-sol` |
| 5 | `codex exec` requires a git repo | fails `Not inside a trusted directory` in `/tmp` without `--skip-git-repo-check` | **MEASURED** | the run in #1, first attempt from `/tmp` |

**#3 is the load-bearing fact of this axis.** "2 of 2 routable" reads as two lanes and is one.
`providers.json` already asserts this in prose (*"SECOND HARNESS, NOT ADDED CAPACITY"*); this is the
first time it has been proven by comparing the credentials rather than by citing Pi's docs.

### 2.2 What it costs the BOX (method rule 2: `/usr/bin/footprint -p`, never summed RSS)

Sampled at t=20 s with **4 concurrent** `codex exec` agents running against this repo:

| Unit | footprint TOTAL | dirty | RSS (double-counts — do not sum) | threads | pane? | MCP server? | SessionStart hook? |
|---|---|---|---|---|---|---|---|
| `codex exec` × 4 (measured together) | **72 / 73 / 77 / 79 MB** | 65 MB each | 190–204 MB | 17 | **no** | **no** | **no** |
| `claude.exe --agent-id` deep-research (live, same box, same minute) | **277 MB** | 191 MB | — | — | yes | yes | yes |
| `claude.exe --agent-id` Explore (live, same box, same minute) | **168 MB** | 177 MB | — | — | yes | yes | yes |

Command: `for p in $(pgrep -x codex); do /usr/bin/footprint -p $p | grep TOTAL; done`, and the same
for the two live `claude.exe --agent-id` processes found by `ps -Ao pid,comm,args`.

- **MEASURED:** a `codex exec` agent is **2.2–3.7× lighter** than a live Claude teammate on the one
  instrument that does not double-count, and it takes **no pane** — so it is invisible to the
  terminal wall (~30) that B-series axes care about.
- **INFERRED:** load rose from a 15-min average of 10.43 to a 1-min reading of **13.59** while the 4
  ran (`sysctl -n vm.loadavg`), i.e. ~0.8 runnable threads per unit. Ambient was not controlled, so
  this is directional only. At that rate the `CC_FIRE_MAX_LOAD_PER_CORE=2.0 × 10` gate would admit
  roughly 8–12 of them on top of today's ambient.
- **MEASURED, memory ceiling:** 64 GiB ÷ 75 MB ≈ 870. Memory is nowhere near binding.

### 2.3 What it costs the QUOTA — the number that decides this axis

The meter is in every rollout: `payload.rate_limits.primary` in
`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`.

**MEASURED shape:** `window_minutes: 10080` (7 days) · `plan_type: "plus"` ·
`credits: {has_credits: false, unlimited: false, balance: "0"}` — **no overage, so 100% is a hard
stop** · `secondary: null` — the 5-hour window is **not currently armed on this account**, so the
weekly meter is the only live gate.

Three independent burn measurements, all converging:

| Run | agent-time consumed | meter Δ | **pp per agent-hour** | tokens | source |
|---|---|---|---|---|---|
| Wave 2 (4 concurrent, **all rc 0**, 134/141/184/207 s) | 666 unit-s = 0.185 h | **21.0 → 23.0 = +2.0** | **10.8** | 1,536,047 | this session, `~/.codex/sessions/2026/08/19/` |
| Wave 1 (4 concurrent, killed mid-run at ~75 s each) | 300 unit-s = 0.083 h | 20.0 → 21.0 = +1.0 | 12.0 | 882,650 | this session |
| W2 of the Codex probe, 18 arm runs (2026-08-11) | ~0.45 h (est. 90 s/run) | 22.0 → 27.0 = +5.0 | 11.1 | not recorded | `docs/research/codex-probe-w3-verdict-2026-08-11.md` §7.3 |

Command for the meter: `python3` over the day's rollouts extracting the last
`payload.type == "token_count"` record's `rate_limits.primary.used_percent`.

**Take 11 pp per agent-hour.** Then:

| Derived | Value | Working |
|---|---|---|
| Weekly allowance | 100 pp / 168 h = **0.595 pp/h** | the window is 10080 min |
| **Sustainable concurrent WORKING units** | **0.054** | 0.595 ÷ 11 |
| Agent-hours the whole plan buys | **9.1 / week** = 1.30 / day | 100 ÷ 11 |
| Share of this fleet's sustained capacity | **+0.58%** | 0.054 ÷ 9.4 (parent doc's fleet figure) |
| $ per agent-hour, ChatGPT Plus | **$0.51** | $20/mo ÷ 39.4 agent-h/mo |
| $ per agent-hour, 4× Claude Max (**tier UNVERIFIED**) | **~$0.12** | 9.4 units × 730 h ÷ $800/mo |

**BURST vs SUSTAINED (method rule 6).** These are different products and only one of them is any
good:

- **BURST — real, and the only thing worth keeping.** 4 concurrent agentic reviews finished in 207 s
  wall for 2 pp. The box would take ~10 concurrent; a 10-wide, 10-minute burst costs 1.67 agent-hours
  = **18 pp**, and you get about **five such bursts a week**. Nothing about that touches a Claude
  pane, a Claude meter, or the ~15.
- **SUSTAINED — the lane does not exist.** 0.054 units. To move the operator from ~15 to ~20
  session-equivalents you need +5.6 working units from somewhere; this backend would have to be
  **104× larger** than it is.

**QUOTED, not measured — the upgrade path, because it is the obvious next question.** Third-party
aggregators report Codex Pro at $100/mo ≈ 5× Plus and Pro at $200/mo ≈ 20× Plus; OpenAI's own pricing
page carries only *"additional weekly limits may apply"* with no numbers, so this multiplier cannot be
verified from disk. Taken at face value, **ChatGPT Pro $200/mo buys ≈1.08 sustained working units** —
still less than the ~2.35 units one Claude Max account contributes to the parent doc's fleet figure,
at the same headline price. Sources:
[morphllm](https://www.morphllm.com/codex-pricing) ·
[developers.openai.com/codex/pricing](https://developers.openai.com/codex/pricing) ·
[simplemetrics](https://simplemetrics.xyz/chatgpt-codex-limits-2026/).

### 2.4 What it can actually TAKE — fidelity, measured today

Four independent `codex exec --sandbox read-only` agents were given the same brief: *"Read
`bin/cc-custody`. Name the 3 most likely correctness defects with file:line and a one-sentence
failure scenario."* All four returned rc 0. Every cited line was then checked against the file with
`sed -n`.

| Check | Result | Label |
|---|---|---|
| Citation accuracy (261-line file) | `:205-207` → exactly the `map(select(.marker == $t or .slug == $t)) \| first // empty` slug match. `:103` → exactly the `group_by(.k) \| map(sort_by(.ts) \| last)`. `:144-150` → exactly the `--cwd) shift; CWD="${1:-}"` arg loop. **3/3 on target.** | **MEASURED** |
| Cross-run agreement | **3 of 4** arms independently named `:205` (ambiguous slug discharge) and `:103` (wall-clock ordering, not append order); **3 of 4** named `:229` (parse failure → `[]` → a truncated row hides all outstanding custody) | **MEASURED** |
| Defect reality | All three are real reads of that code — a token matching one row's `marker` and another's `slug` discharges whichever `jq` returns first; `sort_by(.ts)` under a clock rollback orders a return before its open | **MEASURED** (I re-read the file) |
| Long-file citation accuracy | **33–40% of quoted lines land >3 lines from the cited number, and it degrades sharply with file length** (0–6 misses on 185–411-line files; 77/83 misses on 652/982-line files) | **QUOTED** — `codex-probe-w3-verdict-2026-08-11.md` §3, n = 1,420 quoted lines |
| Zero fabrication | Not one quoted line in 1,420 was absent from the file, for any arm, either vendor | **QUOTED** — same source |

Against our four work classes:

| Class | Can Codex take it TODAY? | Evidence |
|---|---|---|
| **Research fan-out** (read-only, high volume) | **Yes on quality, no on volume.** Accurate on ≤~400-line files; unusable citations above ~600. And the meter buys 9.1 agent-hours a week, which is *less* fan-out than one Claude wave. | measured above + W3 §3 |
| **Adversarial / verification review** | **REJECTED, with a verdict already landed.** Over 36 anchored ground-truth defects, **Codex-only unique hits = 0 at every vote threshold** including the most generous; the Claude family caught 3 neither Codex arm did. Its entire contribution is contained in `claude-opus-5`, the slot's own fallback. | `codex-probe-w3-verdict-2026-08-11.md` — 4 blind mixed-vendor judges, 36 cells, robustness-checked |
| **Mechanical implementation** (well-specified, testable) | **Never attempted here.** `--sandbox workspace-write` exists; `grep 'codex exec' ~/.claude/logs/bash-commands.log \| grep workspace-write` returns **0 real invocations** (the 2 hits are this session's own greps). `git log --all --format='%an' \| sort -u` → `Chris Ren`, `Claude`, `renchris`, `t` — **no commit in this repo has ever been authored by a Codex run**, across 81 rollouts in August. | **MEASURED** |
| **Judgment / architecture** | **No.** Same probe: `claude-opus-5 @max` beat both Codex arms *and* the Fable incumbent on ground-truth recall (13 vs 10 vs 9 of 36) and on unique hits (2 vs 0 vs 0). | W3 §6 |
| **Our own infra** (needs repo context + our rails) | **No, by construction.** `ls AGENTS.md` → absent. `~/.codex/skills` → empty. `~/.codex/memories` → empty. It arrives with **no CLAUDE.md, no hooks, no skills, no memory, no MCP, no ledger, no `/ship`, no custody, no backlog** — every convention has to be re-shipped inside each brief. | **MEASURED** |

### 2.5 What is MISSING to route work to them

| Question | Answer | Command |
|---|---|---|
| Does `handoff-fire.sh` know about Codex? | **No.** 0 hits for `codex`/`provider`/`non-claude` in 8,000 lines. | `grep -niE 'codex\|provider\|non-claude' scripts/handoff-fire.sh` |
| Is there ANY dispatch path in the repo? | **No.** `grep -rniE '\bcodex exec\b\|pi --print' bin scripts hooks` → **zero matches**. | as shown |
| What integration exists at all? | **Read-only readout only.** `providers.json` (SSOT) + `bin/claude-accounts --agents` (renderer) tell you it *is* routable; nothing routes. The one place we adopted a Codex asset — the `codex-security` skill — deliberately runs the methodology **on Claude**: *"no Codex CLI, no Codex desktop app, no ChatGPT/Codex subscription."* | `skills/codex-security/SKILL.md:4` |
| Minimum viable integration | A `bin/cc-codex` dispatcher: brief-file in, `codex exec --sandbox read-only --skip-git-repo-check` out, capture the rollout's `used_percent` before/after into the accounts ledger, plus one bats suite. ~100–150 LOC, ~1 agent-day including the live-layer symlink (it is an **ADD**, so `LIVE_ADDS` breaches at a lag of 1 — the converger must run or every call site is a silent no-op). | scoped, not built |
| Worth it vs just running more cloud sessions? | **No.** The MVI returns **+0.054 working units**. The parent wave's own off-box axis puts working cloud sessions at **0 today, ~10 reachable in one build wave** (`scaling-bottlenecks-2026-08-09/06-offbox.md`). One build wave on the cloud lane is worth ~185× one build wave here. | comparison |

---

## 3 · WHAT I COULD NOT MEASURE, AND WHY

1. **The Pro/Business multiplier.** Not held, so not measurable from disk. OpenAI does not publish
   weekly numbers; the 5× / 20× figures are third-party aggregation and are labelled QUOTED. The
   verdict does not depend on them — at the quoted 20× the answer is still "one more Claude Max beats
   it at the same price."
2. **The Claude accounts' plan tier.** `accounts.json` carries no `plan`/`tier` field
   (`spend.usage_credits_authorized=false`, `router.KMAX=8`, `KMAX_RESIDENT=40` and nothing about
   subscription level), so the `$0.12/agent-hour` figure assumes 4 × Max-20x at $200. **If the tier is
   lower the Claude-side dollar advantage grows, not shrinks** — the comparison is conservative in the
   direction that matters.
3. **A clean load attribution for `codex exec`.** Method rule 3 forbids inferring a load numerator.
   Ambient was ~10.4 and moved to 13.6 with 4 running; I did not run a paired no-Codex control in the
   same minute, so ~0.8 runnable threads/unit is INFERRED and should not be quoted as measured.
4. **Why wave 1's four agents were killed mid-run.** All four `codex exec` processes vanished
   mid-stream (output truncates inside a file read) while the parent `wait` was live; wave 2 with the
   same shape completed cleanly at rc 0. Unexplained, not reproduced, **not encoded as a Codex
   property** — one transient event is exactly the anti-capture case.
5. **Whether Pi's own meter reads the same counter.** I proved the *credential* is identical
   (`accountId` byte-for-byte), which is sufficient for the capacity conclusion. I did not run a
   paired `pi --print` → re-read-`codex`-meter differential, so "Pi's spend appears in Codex's
   `used_percent`" is INFERRED from shared identity rather than observed.
6. **Gemini CLI's plan tier** — still UNKNOWN from disk after the 2026-08-10 sweep and still UNKNOWN
   today, so the cost gate still cannot clear it. Unchanged, not re-derived.

---

## 4 · THE DECISION THIS AXIS CHANGES

**Take the L4 row out of the capacity ledger.** The parent doc lists Codex CLI and Pi·Codex as the
only units consuming neither ceiling and marks them **"YES, already routable."** Both halves are
true and the row is still misleading, because routable says nothing about *how much*. Measured:
**two harnesses, one meter, 0.054 sustainable working units, +0.6% of the fleet.** It should read
**"routable, and worth 0.6% — burst tool, not a lane."**

Three consequences, in the order they change what gets built:

1. **Do not build the dispatcher, and do not buy the upgrade.** An agent-day of integration returns
   half a percent. At the quoted 20×, ChatGPT Pro at $200/mo returns ~1.08 units where a fifth Claude
   Max returns ~2.35 at the same price. **If the operator is willing to spend $200/month on capacity,
   the answer is another Claude Max account, not another vendor.**
2. **Keep exactly one use, unwired.** Hand-fire `codex exec --sandbox read-only
   --skip-git-repo-check` for a ≤400-line-file read-only review when the *Claude* meter is what you
   are protecting — 4 concurrent, ~3 minutes, 2 pp, no pane, no Claude quota, and today's run shows
   the findings are real. Five such bursts a week is the honest budget. Above ~600 lines it stops
   being useful: a third of its citations point at the wrong line.
3. **Stop treating "a different vendor" as a way out of the quota wall.** This was the axis's best
   hope and it fails on the *same* axis Claude fails on, four times harder: the box could run 15 of
   these at once, and the subscription pays for **36 minutes** of that. The wave's capacity answer
   has to come from the Claude side — the cloud lane (0 working today, ~10 in one build wave) or the
   duty cycle — not from here.

**Sources for the QUOTED figures:**
[Codex Pricing 2026 — morphllm](https://www.morphllm.com/codex-pricing) ·
[Pricing | OpenAI Codex](https://developers.openai.com/codex/pricing) ·
[ChatGPT Codex Limits 2026 — SimpleMetrics](https://simplemetrics.xyz/chatgpt-codex-limits-2026/)
