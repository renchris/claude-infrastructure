# A5 — OUR OWN SLOT ACCOUNTING: which of our gates does each orchestration unit pass through?

Date: 2026-08-19 · box: MacBookPro18,2 (M1 Max, hw.ncpu=10), CC 2.1.220 · all measurements live, read-only.
Repo: `/Users/chrisren/Development/claude-infrastructure` @ `main` (9709c99d3).

---

## 1. VERDICT (≤5 lines)

1. **A Dynamic Workflow agent passes through NO gate of ours.** MEASURED: my own workflow minted 9 agents at
   11:43:46–49Z; the `Agent` PreToolUse hook wrote **0** rows in that window while the same ledger took **874**
   other rows — so no capacity term, no spawn budget, no depth cap, no lineage cap, no model allowlist ran.
2. **A named `Agent({name})` teammate passes through the MOST gates of any unit** — it hits `agent-teams-enforce.sh`
   *and* becomes a real OS process in its own kitty pane, so it is also charged by every process census we own.
3. **The two capacity gates measure DIFFERENT things and neither is a superset**: `handoff-fire` charges
   load(2.0/core)+headroom; the Agent tool charges headroom+compressor-segments+active(8)+operator-reserve with
   `CC_ADMIT_LOAD_TERM=off`. Measured 11:51Z: the fire gate said REFUSE (3.14/core) while the Agent gate said ADMIT.
4. **The router's burn census `k_work` is blind to every in-process agent.** MEASURED right now: 11 transcripts it
   can see vs **19 it cannot** (63% of live writers), because agent transcripts live 3+ levels below the slug.
5. **`CC_FIRE_MAX_LOAD_PER_CORE=2.0` is a cap on ~4–8 *mid-turn* sessions, not on ~15 resident ones** — 20 resident
   trees are live right now at 2.27/core. It refused **19 fires in 9 days (8.6% of production evaluations)**.

---

## 2. THE MATRIX — 5 units × our gates

Units:
**U1** plain `Agent()` subagent (no name) · **U2** `Agent({name})` teammate/assignee · **U3** Dynamic-Workflow agent ·
**U4** `handoff-fire.sh` dispatched pane session · **U5** backgrounded/daemon session (`claude.exe daemon run`, `--bg-pty-host`).

### (a) `handoff-fire.sh` capacity gate — `capacity_gate()`

| Unit | Passes it? | Citation |
|---|---|---|
| U1 | **NO** — never invokes handoff-fire | call site is `scripts/handoff-fire.sh:6354` only |
| U2 | **NO** — the teammate pane is launched by `bin/it2-kitty:318` → `bin/cc-pane-runner`, not by handoff-fire | `bin/it2-kitty:300,318` |
| U3 | **NO** | same |
| U4 | **YES** for a net-new fire; **EXEMPT** for `--recycle` | `scripts/handoff-fire.sh:6353-6354` `if [ "$RECYCLE" = 0 ]; then capacity_gate \|\| exit 9; fi` |
| U5 | **NO** (launchd/daemon path) | — |

**Every term `capacity_gate()` evaluates, in order** (`scripts/handoff-fire.sh:4368-4560`):

| # | Term / branch | Line | Outcome |
|---|---|---|---|
| 0 | `CC_FIRE_CAPACITY_GATE=off` kill switch | 4375 | admit, `basis:"gate-off"` |
| 1 | **cloud venue branch (G5)** — router binary unreachable | 4409-4415 | **rc 9** `cloud-router-absent` |
| 2 | cloud — `claude-accounts --route general` rc 3 (limits UNREADABLE) | 4421-4427 | **rc 9** `cloud-account-headroom` |
| 3 | cloud — rc≠0 / empty / `none` (no account routable by policy) | 4429-4434 | **rc 9** `cloud-account-policy` |
| 4 | cloud ADMIT | 4435-4442 | rc 0, `emit_gate_admit cloud measured` |
| 5 | `cc_hw_ready` / capacity-admit.sh absent | 4453-4457 | admit **fail-OPEN**, `basis:"absent"` |
| 6 | operator presence read (record-only, no reserve applied here) | 4463-4465 | annotates the row |
| 7 | `hw.ncpu` unreadable via resolved sysctl | 4480-4483 | admit fail-open |
| 8 | `vm.loadavg` unreadable | 4484-4487 | admit fail-open |
| 9 | `CC_FIRE_MAX_LOAD_PER_CORE` non-numeric | 4488-4490 | admit fail-open |
| 10 | `ncpu == 0` | 4492-4493 | admit fail-open |
| 11 | **LOAD**: load1/ncpu > ceiling (default `2.0`, `:4470`) | 4496-4508 | **rc 9** `reason:"capacity"` — bounded by `_cc_fire_bound` |
| 12 | `CC_FIRE_HEADROOM_GATE=off` | 4513-4519 | admit `basis:"load-only"` |
| 13 | `CC_FIRE_MIN_HEADROOM_GB` non-numeric / headroom unreadable | 4531-4540 | admit fail-open |
| 14 | **HEADROOM**: reclaimable GB < floor (default 4) | 4542-4549 | **rc 9** `reason:"headroom"` — bounded |
| 15 | both terms cleared | 4553-4556 | rc 0, `basis:"measured"` |
| — | refusal-budget release (`CC_FIRE_ADMIT_BUDGET`, default 1) | 4339, 4345, 4350 | **admits anyway + pages**, `basis:"budget-untrackable"` / `"budget-expired"` |

Return codes: **0 = admit**, **9 = refuse** (the caller turns any non-zero into `exit 9`). There is no other rc.

### (b) Account router — `KMAX` / `k` / `k_work` / `k_eff` census

The router charges `k_eff = (k_work if measurable else k) + k_phantom` (`bin/claude-accounts:1482-1489`), against
`k_cap` = `KMAX` (8) when the charge came from `k_work`, else `KMAX_RESIDENT` (40) (`bin/claude-accounts:1510-1539`).

| Instrument | What it actually counts | Citation |
|---|---|---|
| `k` (pane/process census) | `ps -wwEo command=` rows whose **argv[0]** is `claude`, `*/claude`, `*claude.exe`, or contains `cli.js`; `-p/--print/--version` in argv[1..6] skipped; attributed by the **LAST** `CLAUDE_CONFIG_DIR=` in the ps -E line | `bin/claude-accounts:472-513` |
| `k_work` (burn census) | `.jsonl` files **exactly one level** inside `<config>/projects/<slug>/` with mtime ≤ `KWORK_WINDOW_MIN` (10 min). `os.scandir(pdir)` → `os.scandir(slug.path)` — **no recursion** | `bin/claude-accounts:536-620`, walk at `:583-608` |
| `k_phantom` | fire-time `--assign` rows for `ASSIGN_TTL_MIN` (15 min) | `bin/claude-accounts:1354-1361` |

| Unit | counted by `k`? | counted by `k_work`? | Citation / measurement |
|---|---|---|---|
| U1 plain subagent | **NO** (in-process — mints no OS process) | **NO** — its transcript is `…/<sid>/subagents/agent-<id>.jsonl`, depth 3 | `scripts/handoff-fire.sh:3325` names the path; walk depth at `bin/claude-accounts:583-608` |
| U2 named teammate | **YES** — argv[0] ends `claude.exe`, no `--agent-id` exclusion anywhere in the matcher | **YES**, but only via its *own* session transcript if it writes one at slug level | measured: 3 of 19 census-matched rows are `--agent-id` (§3 cmd C2) |
| U3 workflow agent | **NO** | **NO** — `…/<sid>/subagents/workflows/wf_<id>/agent-<id>.jsonl`, depth 5 | measured (§3 cmd C6) |
| U4 dispatched session | **YES** | **YES** | — |
| U5 daemon / bg-pty-host | **YES if alive** (argv[0] ends `claude.exe`; `daemon`/`--bg-pty-host` are not `-p/--print/--version`) | NO | `bin/claude-accounts:485-499`; none alive at probe time, so this cell is **INFERRED from the matcher**, not observed |

The repo-memory failure mode `pgrep -f X counts sessions that MENTION X` **does not apply here** — the matcher is
anchored on `toks[0]` (argv position 0), and the headless filter only reads `toks[1:7]`
(`bin/claude-accounts:499-504`). Same anchoring in `scripts/assignee-pane-residency.sh:18,146-147`, which explicitly
cites that memory and intersects the argv match with a known member set.

`bin/cc-wave-plan` reads the SAME integer for its urgency bound — allowance = `min(CC_WAVE_MAX_PER_ACCT_URGENT,
KMAX − k_eff)`, floor 0, `KMAX` read from the SSOT `accounts.json` (`bin/cc-wave-plan:441-525`; `:495-500` mirrors
`k_eff`). An unreadable `KMAX` = **no bound** (`bin/cc-wave-plan:460`).

### (c) The `Agent` PreToolUse hooks

`~/.claude/settings.json:487` — `"matcher": "Agent"` → `hooks/agent-teams-enforce.sh` + `hooks/frontier-spawn-gate.sh`.

| Gate inside `agent-teams-enforce.sh` | Line | U1 | U2 | U3 |
|---|---|---|---|---|
| worker-claim duplicate-worker deny | 119-123 | ✔ | ✔ | ✘ |
| **machine capacity** `cc_capacity_admit agent-tool` with `CC_ADMIT_LOAD_TERM=off` | 212-224 | ✔ | ✔ | ✘ |
| spawn **depth** cap (`CC_SPAWN_MAX_DEPTH`) | 416-420 | ✔ | ✔ | ✘ |
| per-session **spawn budget** (`CC_SPAWN_MAX_PER_SESSION`) | 428-432 | ✔ | ✔ | ✘ |
| spawn **lineage generation** cap | 481-485 | ✔ | ✔ | ✘ |
| teammate **model allowlist** | 496-533 | n/a | ✔ | ✘ |
| `frontier-spawn-gate.sh` (frontier window) | whole file, 67 lines | ✔ | ✔ | ✘ |

The capacity terms actually evaluated for the Agent caller, measured by running the hook's exact invocation on
isolated state: `terms:"headroom,segments,active"` (§3 cmd C8). Their definitions:
`scripts/lib/capacity-admit.sh:622` (headroom floor 4 GB), `:667` (compressor segments, ceiling 50%),
`:708-719` (**ACTIVE ceiling 8**), `:741-747` (`reserve-headroom`), `:761-773` (`reserve-active`),
`:776-790` (`reserve-slots` against `cc_sp_trees` and a **54**-session ceiling).

Two censuses feed those terms, and they classify our units differently:

* `cc_sp_trees()` (`scripts/lib/spawn-presence.sh:153-181`) — `ps -eo pid=,ppid=,args=`, family = argv ending
  `claude-code/bin/claude.exe` or `node_modules/.bin/claude`, **skipping any process whose parent is in-family**.
  MEASURED: a named teammate's parent is `/bin/bash …/bin/cc-pane-runner`, i.e. **not** in-family, so **a teammate
  counts as its own tree** (§3 cmd C3). U1/U3 mint no process ⇒ 0.
* `cc_sp_active()` (`scripts/lib/spawn-presence.sh:253-330`) — distinct claude-ancestor pids among `kind:"prompt"`
  beats younger than `CC_BEAT_LIVE_MAX_S` (900 s), positive-controlled on its own pid. A teammate writes its **own**
  beat under its **own** pid (MEASURED: beats for pids 28505/17602 = live `--agent-id` processes, §3 cmd C4), so U2
  charges the active term. U1/U3 fire no `UserPromptSubmit`, so **N in-process agents charge the active term 0**.

### (d) Teammate caps / teardown

* The **6-concurrent-teammate rule is PROSE ONLY**. Repo-wide grep for an enforcing constant finds exactly one hit,
  in a skill document: `skills/agent-teams/SKILL.md:317`. No hook, no bin, no script implements it (§3 cmd C9).
* `bin/cc-teardown` targets a **session** — kill the claude process + close its pane + re-observe
  (`bin/cc-teardown:6-12`). U2/U4/U5 are in scope; U1/U3 have no process and no pane, so teardown is n/a and
  `shutdown_request` is the only lever (and only for U2).

### (e) Side-artifacts created per unit

| Artifact | U1 | U2 | U3 | U4 | U5 | Citation |
|---|---|---|---|---|---|---|
| git worktree | ✘ | ✘ (inherits lead's cwd) | ✘ | ✔ `--worktree` | ✘ | `scripts/handoff-fire.sh:7810` |
| mailbox (pane-UUID-keyed) | ✘ | ✔ (has a pane) | ✘ | ✔ | ✘ | `hooks/lib/mailbox-pending.sh:43,61` |
| `cc-registry` row | ✘ | **✔ MEASURED** | ✘ | ✔ | ✘ | `hooks/session-register.sh:165`; §3 cmd C5 |
| custody debt | ✘ | ✘ | ✘ | ✔ iff `--notify-back` | ✘ | `bin/cc-custody:12-21`, `scripts/handoff-fire.sh:2733-2738` |
| own transcript | ✔ (nested) | ✔ (slug-level) | ✔ (nested) | ✔ (slug-level) | ✔ | §3 cmd C6 |

---

## 3. THE NUMBERS, each with the command that produced it

**C1 — the fire gate's real refusals (MEASURED).**
```
jq -r 'select(.gate=="capacity" and .verdict=="refuse") | .ts[0:10]' ~/.claude/logs/handoffs.jsonl | sort | uniq -c
   6 2026-08-11    2 2026-08-12    1 2026-08-13    1 2026-08-16    1 2026-08-17    7 2026-08-18    1 2026-08-19
```
19 refusals, file spans `2026-08-10T20:12:30Z … 2026-08-19T11:36:05Z`. Split by `under_test`:
```
jq -r 'select(.gate=="capacity") | "\(.basis) under_test=\(.under_test)"' ~/.claude/logs/handoffs.jsonl | sort | uniq -c
  measured under_test=false 198 · measured under_test=true 12
  gate-off  under_test=true 196 · gate-off  under_test=false 5
  refuse    under_test=false 19
```
**Production refusal rate = 19 / (198+19+5) = 8.6%.** ⚠ This CORRECTS `scripts/handoff-fire.sh:527`, which reads
"453 of 633 admits carry `basis:\"gate-off\"`" — in the current window **196 of the 201 gate-off rows are the test
harness** (`scripts/test-hermeticity-lint.sh:2284` pins `CC_FIRE_CAPACITY_GATE=off` in setup). The live gate is
~98% measured, not ~72% disabled.

Newest three refusal details, verbatim:
```
2026-08-18T15:48:36Z  load 20.84 on 10 cores = 2.08/core > ceiling 2.0/core · operator present
2026-08-18T23:25:46Z  load 20.62 on 10 cores = 2.06/core > ceiling 2.0/core · operator present
2026-08-19T11:19:51Z  load 118.95 on 10 cores = 11.89/core > ceiling 2.0/core · operator present
```

**C2 — the router's pane census sees agents (MEASURED).** Replicated `concurrency()`'s matcher verbatim
(`/usr/bin/python3`, `ps -wwEo command=`):
```
TOTAL MATCHED BY concurrency(): 19   →  16 launcher sessions · 3 "--agent-id" AGENT processes
per config_dir: .claude-tertiary 9 · .claude-secondary 5 · .claude-quaternary 3 · .claude-next 2
```
A named agent is not excluded anywhere in that matcher.

**C3 — tree census counts a teammate as its own tree (MEASURED).**
```
. scripts/lib/spawn-presence.sh; cc_sp_trees   → 19 (later 20)
ps -eo pid=,ppid=,args= | ... parentage:
  AGENT pid=8435  ppid=7723  parent=[/bin/bash …/claude-infrastructure/bin/cc-pane-runner]
  AGENT pid=17602 ppid=17203 parent=[/bin/bash …/bin/cc-pane-runner]
  AGENT pid=28505 ppid=27534 parent=[/bin/bash …/bin/cc-pane-runner]
full argv: claude.exe --agent-id A9-prior-art@session-84bde2e9 --agent-name A9-prior-art
           --team-name session-84bde2e9 --parent-session-id 84bde2e9-… --agent-type deep-research
```
Parent is a bash wrapper, not in-family ⇒ each teammate is its own tree, and its grandparent is a kitty
`kitten run-shell` — i.e. **a real pane**.

**C4 — teammates write their own beats, so they charge `cc_sp_active` (MEASURED).**
```
python3 over ~/.claude/cc-beats/*.json  (1808 files)
  t-771s kind=stop pid=28505 AGENT sid=e895e634
  t-801s kind=stop pid=17602 AGENT sid=ee2b25fc
. scripts/lib/spawn-presence.sh; cc_sp_active → 3   (trees 19-20 at the same instant)
```

**C5 — teammates get registry rows; workflow agents do not (MEASURED).**
```
ls ~/.claude/cc-registry/*.json | wc -l  → 19-23
grep -l <sid> ~/.claude/cc-registry/*.json | wc -l
  e895e634 (teammate) → 1     ee2b25fc (teammate) → 1
  84bde2e9 (lead)     → 1     161874bb (session) → 1
```

**C6 — `k_work` is blind to in-process agents (MEASURED).** Reference file 10 min old, `find -newer`:
```
.claude            k_work-VISIBLE=2   INVISIBLE=0
.claude-secondary  k_work-VISIBLE=3   INVISIBLE=9
.claude-tertiary   k_work-VISIBLE=6   INVISIBLE=0
.claude-quaternary k_work-VISIBLE=0   INVISIBLE=10
TOTAL              visible=11         invisible=19        (63% of live writers unseen)
nested path shapes: 17 × subagents/workflows/wf_<id>/agent-<id>.jsonl
                     2 × subagents/workflows/wf_<id>/journal.jsonl
```
`.claude-quaternary` is the sharp case: **0 visible, 10 invisible** — an account running ten concurrent workflow
agents whose `k_work` reads 0 for all of them, so the router scores it as idle and routes the next fire onto it.
This also **falsifies the docstring at `bin/claude-accounts:543-546`** — *"active subagents append to their own
.jsonl **siblings** and are burners too"*. They are not siblings; they are 3–5 levels below the slug, and the walk
does not recurse.

**C7 — the two gates disagree at the same instant (MEASURED, isolated state).**
```
/usr/sbin/sysctl -n vm.loadavg           → { 22.70 24.36 28.98 }   (2.27/core, over the 2.0 ceiling)
cc_hw_load_verdict 31.38 10 2.0          → REFUSE 3.14             (what handoff-fire would return: rc 9)
CC_ADMIT_LOAD_TERM=off cc_capacity_admit agent-tool "A5 probe"  → rc 0
  "ADMIT — load term off · reclaimable 26.30GB (floor 4GB) · segments 9.00% of limit (ceiling 50%)
   · 2 sessions mid-turn (active ceiling 8)"   basis:"headroom-only"  reserve:"6 slots + 6GB"
```
(Probe pointed `CC_ADMIT_STATE_DIR` / `CC_ADMIT_IDL` at a `mktemp -d`, so no live budget counter or ledger was
touched; temp dir removed.)

**C8 — Dynamic Workflow agents bypass the Agent hook entirely (MEASURED, positive-controlled).**
Every `agent-tool` row the hook has written today:
```
jq -r 'select(.gate=="capacity-admit" and .caller=="agent-tool")' ~/.claude/autonomy/idl.jsonl
  08:37:02Z sid=a172aeb9 what=Explore spawn        admit
  11:29:42Z … 11:31:50Z  sid=84bde2e9  what=deep-research spawn  admit  ×11
```
My own workflow's agent transcripts were created at (local PDT = UTC−7):
```
ls -l …/f285654f-…/subagents/workflows/wf_06556f35-03a/
  04:43:46 … 04:43:49  →  9 agent-*.jsonl  +  journal.jsonl     ≡ 11:43:46–49Z
```
**Positive control on the ledger at that exact instant:**
```
jq 'select(.ts>="2026-08-19T11:42:00Z" and .ts<="2026-08-19T11:46:00Z")' ~/.claude/autonomy/idl.jsonl
  total rows in window  = 874
  caller=="agent-tool"  = 0
```
The IDL was hot (874 rows in four minutes) and recorded zero Agent-tool evaluations while nine workflow agents were
minted. **The `Agent` PreToolUse matcher does not fire for Dynamic-Workflow agents.**

**C9 — the 6-teammate cap is not enforced anywhere (MEASURED, negative with control).**
```
grep -rnE "6 concurrent|MAX_TEAMMATE|CC_TEAM_MAX|concurrent teammates" hooks/ bin/ scripts/ skills/agent-teams
  skills/agent-teams/SKILL.md:317   ← the only hit that is about teammates
```
Control: the same grep style finds the real caps (`CC_SPAWN_MAX_DEPTH`, `CC_SPAWN_MAX_PER_SESSION`,
`CC_LINEAGE_MAX_GEN`) in `hooks/agent-teams-enforce.sh`, so the pattern is capable of finding an enforced cap.

**C10 — what `2.0/core` implies as a session count.**
Ceiling = `2.0 × hw.ncpu(10)` = **load1 20.0**.
QUOTED-FROM-DOC (`scripts/lib/capacity-admit.sh:695-700`): 2.5–5 runnable threads per genuinely-ACTIVE session
(load1 27.4 → 44.4 at 9 all-active), giving **~4–8 concurrent actives — "which is also what all 127/127 historic
gate refusals correspond to."**
MEASURED counter-evidence that this is *not* a resident-session cap: at load 22.70 (2.27/core, over the ceiling)
the box was carrying **20 live session trees with only 3 mid-turn**. The gate is a cap on **concurrent turns**,
not on residency; `spawn-presence.sh`'s own resident ceiling is a separate constant, **54**
(`scripts/lib/capacity-admit.sh:778` → `CC_SP_DEFAULT_CEILING:-54`). The operator's "~15" matches neither number.

---

## 4. THE CELLS THAT ARE WRONG

Ranked by how much real resource escapes the gate built to protect it.

**W1 — A Dynamic Workflow agent consumes a full agent's worth of API burn and context and passes through NONE of
our five Agent-tool gates.** Evidence C8. It escapes: capacity (headroom/segments/active/reserve), the per-session
spawn budget, the depth cap, the lineage generation cap, the model allowlist, the worker-claim duplicate gate, and
the frontier window gate. The spawn budget's own deny text (`hooks/agent-teams-enforce.sh:428`) says the cap exists
because an unbounded fan-out "reached 224 spawns / 167 sessions" and ignited kernel watchdog panics — a workflow
can reproduce exactly that shape with the counter reading zero. **This is the operator's actual risk when they
switch orchestration units: moving a wave from `Agent()` to a Dynamic Workflow silently removes seven gates.**

**W2 — `k_work`, the router's burn instrument, cannot see in-process agents; measured 19 invisible vs 11 visible
(63%).** Evidence C6. Consequence, and it is the exact defect `k_work` was built to fix, inverted: an account whose
lead session is *waiting on* ten workflow agents writes nothing at slug level, so `k_work` = 0, so `k_eff` = 0, so
`_excluded`'s `KMAX` cap never binds and the router's urgency score ranks it as the **idlest** account — and
`bin/cc-wave-plan:490-500` then hands it the **widest** allowance (`KMAX − 0`). `.claude-quaternary` was in exactly
that state at probe time. The docstring at `bin/claude-accounts:543-546` asserts the opposite and is false.

**W3 — `cc_sp_active` (ceiling 8, the term the Agent gate leans on hardest) counts a fan-out of N in-process agents
as 1.** Evidence C4 + `spawn-presence.sh:253-330` (it dedupes to the nearest claude ancestor, and U1/U3 share the
lead's). The deny text at `hooks/agent-teams-enforce.sh:220` sells `active` as "the ceiling the whole design point
rests on… 2.5-5 runnable threads arrive with every ACTIVE session" — but a 13-agent in-process wave is 13 concurrent
turns charging 1. The term is honest for U2/U4 and structurally blind for U1/U3, which are the highest-volume units.

**W4 — the fire gate's LOAD term and the Agent gate's term set are disjoint in both directions.** Evidence C7. A
dispatched session is refused at 2.0/core but is never charged compressor segments, the active ceiling, or the
54-tree reserve; an Agent spawn is charged all three but is explicitly exempt from load
(`hooks/agent-teams-enforce.sh:213` `CC_ADMIT_LOAD_TERM=off`). At 11:51Z the box simultaneously said "no new
dispatched session" and "yes to unlimited subagents". The reasoning for that asymmetry is documented and defensible
(`agent-teams-enforce.sh:152-195`: load is neither attributable nor sheddable), but the *net* is that the
cheapest-to-spawn unit faces the weakest wall.

**W5 — the 6-concurrent-teammate cap is documentation, not a gate.** Evidence C9. Teammates are the ONLY unit that
costs a real pane + a ~460–550 MB process + a registry row + a mailbox, and the only cap on their count lives in a
markdown file. The enforced caps (depth, per-session budget, generation) bound the *shape* of the tree, not the
*width* of one session's teammate roster.

**W6 — `k` (the router's pane census) counts the daemon and the bg-pty-host as live sessions.** INFERRED from the
matcher (`bin/claude-accounts:485-499`): argv[0] `…/bin/claude.exe` matches, and `daemon run --origin …` /
`--bg-pty-host …` contain none of `-p/--print/--version`, so they are not filtered. Not observed live — no daemon
was running at probe time (§5). If true, every account's `k` carries a permanent +1 or +2 of non-session processes,
which matters because `k` is the *stricter* fallback the router degrades to whenever the `k_work` walk overruns.

**Correct cells worth stating, so the matrix is not read as all-bad:** U2 (named teammate) is charged by every
census we own — `k`, `cc_sp_trees`, `cc_sp_active`, the registry, the mailbox, teardown — and passes both the Agent
hook and, being a real pane, the pane censuses. U4 (dispatched session) is charged by everything except the
segments/active/tree terms. The accounting is sound for the two units that cost the most per unit; it fails for the
two that are spawned in the largest numbers.

---

## 5. WHAT I TRIED THAT DID NOT WORK / COULD NOT BE MEASURED

* **`bin/cc-panes` does not exist.** The axis brief names it; the tree has `bin/cc-pane` (a pane primitive) and
  `bin/cc-sessions` (registry rows). `bin/cc-where:26` says so explicitly: *"it is deliberately NOT called
  `cc-panes`, one letter off `cc-pane`."*
* **`bin/cc-discover` is not a pane census.** It is the backlog discovery feed (critics C1–C4 refilling
  `cc-backlog`, `bin/cc-discover:5-18`). It has no bearing on slot accounting. My first grep of it returned nothing;
  the positive control was reading its 40-line header, which showed the grep was correct and the premise wrong.
* **BSD `find -newermt '-10 minutes'` silently matches nothing on macOS.** My first `k_work`-visibility measurement
  returned `0` across all four config roots — which I nearly reported as "no fresh transcripts". The positive
  control (`find … | xargs stat -f '%m %N' | sort -rn | head -1`) returned a file modified **that second**, proving
  the null was the instrument. Re-run with `touch -t $(date -v-10M …)` + `find -newer <ref>` gave C6. *This is the
  measurement in this file that was wrong first and would have inverted W2's conclusion.*
* **`grep` of `cli.js` for workflow tool names: the file does not exist at that path.** 2.1.220 ships
  `bin/claude.exe` + `cli-wrapper.cjs`, no `cli.js` bundle. So I could not determine the *tool name* a Dynamic
  Workflow uses, only that whatever it is, it is not matched by `"matcher": "Agent"` (C8 is behavioural, not
  name-based — which is the stronger evidence anyway).
* **U5 (daemon / bg-pty-host) could not be observed.** The machine-facts brief listed `claude.exe daemon run`
  (pid 59451) and `--bg-pty-host` as live; at my probe time `ps | grep -E "daemon run|bg-pty-host"` returned
  nothing. Every U5 cell in the matrix is INFERRED from the matcher source, not measured.
* **I did not spawn a probe agent or a probe fire.** Everything is read-only against the live fleet plus one
  `cc_capacity_admit` call with its state dir and ledger redirected to a `mktemp -d` (removed afterwards). No
  process was killed, stopped, or closed.
* **`concurrency()`'s `None` contract could not be exercised** — I did not want to break `ps` on a live box.
  The claim that a failed `ps` returns `None` (not all-zero) is QUOTED-FROM-DOC (`bin/claude-accounts:435-456`).

---

## 6. OPEN QUESTIONS FOR THE VERIFIER

1. **Is W1 a matcher gap or a tool-name gap?** C8 proves behaviourally that the hook does not run for workflow
   agents. It does not establish *why* — a different tool name (so `"matcher": "Agent"` misses), or a spawn path
   that does not run PreToolUse at all. The fix differs: a matcher edit vs. a new chokepoint. Someone with the
   2.1.220 tool list should settle it.
2. **Does a plain unnamed `Agent()` on 2.1.220 stay in-process, or does it also become a `cc-pane-runner` pane?**
   The three live `--agent-id` processes carry `--agent-name` AND `--team-name session-<sid>` — an *implicit* team
   name that may be auto-generated for every Agent call, in which case U1 and U2 are the same unit on this binary
   and my U1 row (mints no process) is wrong. My own wave is the counter-example (13 agents, 0 processes) but it is
   a *workflow*, so it does not settle U1. **This is the cell most likely to be wrong.**
3. **Was the "127/127 historic gate refusals" figure computed over a window that included test rows?** My window
   (2026-08-10→19) shows 19 refusals, all `under_test:false`. If the historic 127 included harness fires, the
   "~4–8 concurrent actives" calibration inherits the contamination.
4. **Is `k`'s daemon/bg-pty-host inclusion (W6) real?** Needs one observation while a daemon is alive:
   `ps -wwEo command= | grep -c "claude.exe daemon"` cross-checked against `claude-accounts --route-meta`'s `k=`.
5. **Should `k_work` recurse, or should agents be charged to their lead?** Recursing would make `k_work` count 10
   workflow agents as 10 burners against `KMAX`=8 — which may be correct (they *are* 10 concurrent API streams) or
   may over-refuse (they share one 5h window position). The right answer decides whether W2's fix is a `os.walk`
   or a new term.
6. **`f285654f` (my own lead session) has no `cc-registry` row** while four sibling sessions do. Either
   `session-register.sh` missed it, or the row is keyed on something my grep did not cover. Worth one check —
   `bin/cc-reaper:289` says it backfills rows for live panes that missed SessionStart, so an unregistered live lead
   is a state something is supposed to heal.
