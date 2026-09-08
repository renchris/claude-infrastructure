# A05 — Permission prompts to allowlist, closed loop

**Wave:** exhaustive-drive 2026-09-08 · **Axis:** A05-permission-loop · **Mode:** read-only.
**Population everywhere below unless stated:** the 3,046 resolved permission prompts in
`~/.claude/autonomy/permission-archive`, 2026-08-09T21:41Z → 2026-09-08T21:41Z, 455 distinct
sessions. 2,905 of them are Bash.

---

## The answer, first

**Permission prompts cost this fleet ~6.3 permanently-blocked sessions at any moment, and the
allowlist cannot buy them back — 43.7% of blocking commands contain a shell construct the harness
gates *before* any rule is matched, and the one hook that can reach them clears 5.4% of today's
prompt population.** The 2026-08-20 rewrite of `hooks/lib/smart-bash-allowlist.py` was a *safety*
fix (it closed a `git commit -m x && <anything>` universal bypass) and the prompt rate roughly
**doubled** as its price: 9.91 → 17.85 prompts per 1,000 Bash calls. The prompt-reduction half was
never delivered, and no producer→proposal→application loop exists: `bin/cc-permission-audit` is
referenced by zero schedulers, its `--prune` result has been owed since 2026-08-21
(`78b76e1a8311`), and **its own read-only dry run is classifier-denied** — measured today at
21:52:57Z, in this session, and logged as row 27 of the refusal ledger.

The four highest-value fixes are all in the decider, not in `settings.json`, and three of them are
parser bugs worth ~260 blocked hours in 30 days.

---

## 1. The cost, measured by two independent instruments

### 1a. Beacon archive (`~/.claude/autonomy/permission-archive`, 3,832 rows all-time)

```
cd ~/.claude/autonomy/permission-archive && cat *.jsonl > /tmp/permarch.jsonl
jq -c --argjson c $(( $(date +%s) - 30*86400 )) 'select(.ts>=$c)' /tmp/permarch.jsonl > /tmp/perm30.jsonl
jq -r '.waited_s' /tmp/perm30.jsonl | awk '{...bucket...}'
```

| wait bucket | prompts | Σ blocked hours |
|---|---:|---:|
| 0–9 s | 1,787 | 1.1 |
| 10–59 s | 440 | 3.1 |
| 1–5 min | 332 | 13.6 |
| 5–30 min | 238 | 49.9 |
| 30 min–2 h | 116 | 125.3 |
| **> 2 h** | **133** | **979.4** |
| **total** | **3,046** | **1,172.5** |

p50 = 8 s · p90 = 1,240 s · p99 = 34,817 s · max = 81,411 s (22.6 h).
**487 prompts (16.0%) carry 1,154.6 h — 98.5% of all blocked time.** The other 84% of prompts cost
17.8 h combined and are not worth optimising.

**Honest bound on `waited_s`.** It is prompt-raised → cleared. Only 56 of the 3,046 rows carry the
`tool_sig`/`cleared_tool_sig` pair the beacon started recording recently; in that decidable
subsample the clearing invocation IS the prompted one in **50/56 = 89%**
(`jq -r 'select(has("tool_sig") and has("cleared_tool_sig")) | if .tool_sig==.cleared_tool_sig then "MATCH" else "MISMATCH" end'`).
For the other 2,990 rows `waited_s` is an **upper bound**. `bin/cc-permission-audit` classifies the
same population as `approved 50 · denied/abandoned 10 · cleared-by-other 359 · unknown 2,627` and
says so in its own docstring — the gap is in the record, not a denial. Point estimate on the
headline: **~1,040 h**, bound 1,172 h.

### 1b. Supervisor IDL — a different instrument, same verdict

`scripts/lead-supervisor.sh:553` writes one `permission_pending` record per sweep per blocked
session. The IDL holds only 2026-09-08 08:22Z onward (13.4 h):

```
/usr/bin/grep 'permission_pending' ~/.claude/autonomy/idl.jsonl > /tmp/pp.jsonl   # 5,117 records
jq -r '[.sid,.age_s]|@tsv' /tmp/pp.jsonl | awk '{if($2>m[$1])m[$1]=$2} END{for(s in m)t+=m[s]; print t/3600, length(m)}'
```

**22 distinct sessions blocked today, 83.8 session-hours, in a 13.4-hour window** — an average of
**6.3 sessions permanently blocked**. Eleven of the 22 sat 5.8–7.9 h each (top: `cf2321de` 7.86 h,
`626edcad` 7.83 h, `ad4e751c` 7.66 h, `e7693813` 7.60 h, `c8a849b6` 7.23 h).

Live snapshot while writing this (`ls /tmp/cc-permission-pending/`, 16:47 local): **4 sessions
blocked**, beacons aged 11–25 min.

### 1c. Who the prompts belong to

Only 322 of the 30-day Bash prompts (11.1%) cross a rule the operator wrote himself
(measured by replaying `crosses_fence` from the decider over the corpus):

| operator rule crossed | prompts |
|---|---:|
| `Bash(git push:*)` | 222 |
| `Bash(git reset --hard:*)` | 69 |
| `Bash(git restore:*)` | 21 |
| `Bash(git stash drop:*)` | 6 |
| `Bash(rm -rf /)` | 4 |

**These must stay prompts.** They are the whole `permissions.ask` list working as designed
(`cc-permission-audit` independently reports "ASK rules actually exercised: git push 30, git
restore 10" over its transcript corpus). The remaining **89%** are auto-mode classifier decisions
over commands no static rule reached.

**The <10 s bucket is the classifier, not the operator.** Fast resolutions cluster at 02:00 (108),
04:00 (170), 19:00 (396), 22:00 (319) America/Los_Angeles — i.e. they resolve at full rate while the
operator is asleep. Slow (>300 s) prompts are flat across all 24 hours (11–28 per hour). So
`PermissionRequest` fires on every Bash call the static allowlist did not cover; the classifier
disposes of ~84% in seconds and escalates the rest to a human who is often not there.

---

## 2. The 2026-08-20 fix doubled the prompt rate, and that was the right trade

Denominator: every Bash tool call, from `~/.claude/logs/bash-commands.log{,.*.gz}`
(`gzcat … | /usr/bin/grep -o -E '^\[2026-[0-9]{2}-[0-9]{2}' | sort | uniq -c`).

| window | prompts | Bash calls | prompts / 1k calls | median day-rate |
|---|---:|---:|---:|---:|
| 2026-08-09 → 08-19 (pre-fix) | 781 | 78,774 | **9.91** | 7.47 |
| 2026-08-21 → 09-06 (post-fix) | 2,084 | 116,732 | **17.85** | 11.02 |

This is not a regression to undo. `hooks/smart-bash-allowlist.sh:52-66` records what the rewrite
removed: rule 1 was anchored only at the start, so `git commit -m x && <anything>` auto-approved
across **8 of the operator's 36 Bash fence rules including two hard `deny` entries**. The prompts
that came back are prompts that should always have been raised. But it means **the fix's stated
prompt-reduction rationale was never realised**, and nothing has closed the gap since.

Confounders named: work mix differs (2026-08-24 alone contributed 611 prompts from one web-scraping
session, `73ace584`); the median day-rate is given because it is robust to that, and it moves the
same way (+48%).

---

## 3. Why `settings.json` allow rules are the wrong lever — two measured ceilings

### 3a. 43.7% of blocking commands are gated before rule matching

`docs/research/permission-matcher-truth-2026-08-20.md` establishes from the binary that five
constructs are evaluated *before* any `Bash(...)` rule is consulted: `$( )`/backticks, `( … )`
subshells, `{ …; }` groups, a trailing `&`, and **any output redirection to a file**. Measured over
the 2,905 Bash prompts of the last 30 days:

| construct | prompts | share |
|---|---:|---:|
| redirection to a file (`> f`, `>> f`) | 956 | 32.9% |
| command substitution `$( )` / backtick | 721 | 24.8% |
| heredoc `<<` | 318 | 10.9% |
| `{ group; }` | 119 | 4.1% |
| trailing `&` | 19 | 0.7% |
| **union (strict)** | **1,270** | **43.7%** |

*(Command: `/private/tmp/.../scratchpad/pregate2.py /tmp/perm30.jsonl`. A sixth arm, bare `( … )`
subshells, added 833 more but on inspection its hits were parentheses inside quoted URLs and
User-Agent strings — reported and then **discarded** rather than counted. The 43.7% is the
conservative floor; the quoted-paren false positives are why the earlier 70.3% figure is not used.)*

**No allow rule of any form reaches those 1,270 commands.** Only a `PreToolUse` hook emitting
`allow` can, because that verdict bypasses the permission system entirely.

### 3b. Auto mode drops the exact rule shapes you would reach for — but only those

This is the result backlog row **`78b76e1a8311`** has owed since 2026-08-21 and that four cloud
dispatches could not produce because no VM has `~/.claude`. Computed here by importing
`auto_mode_dropped()` from `bin/cc-permission-audit` and applying it to the live files
(`/private/tmp/.../scratchpad/drop.py`):

```
/Users/chrisren/.claude-next/settings.json        allow=339  dropped=7 (2.1%)  classifyAllShell=False
/Users/chrisren/.claude-quaternary/settings.json  allow=338  dropped=7 (2.1%)  classifyAllShell=False
/Users/chrisren/.claude-secondary/settings.json   allow=338  dropped=7 (2.1%)  classifyAllShell=False
/Users/chrisren/.claude-tertiary/settings.json    allow=338  dropped=7 (2.1%)  classifyAllShell=False
/Users/chrisren/.claude/settings.json             allow=339  dropped=7 (2.1%)  classifyAllShell=False
FLEET: allow=1692 dropped=35 (2.1%)
```

The 7 dropped per file: `bunx` bare, `env` bare, `node --version:*`, `node -e:*`,
`python --version:*`, `python3 --version:*`, `python3` bare.

**Correction to the obvious reading, stated because I nearly wrote the obvious reading.** The drop
list is *narrow* — 2.1%, and `classifyAllShell` is `false` everywhere, so Bash allow rules survive
auto mode in general. What it drops is the **bare and flag-tail forms of the dangerous-command
list** (`python3`, `node`, `bash`, `sh`, `env`, `xargs`, `npx`, `bunx`, `npm run`, `curl`, `wget`,
`kubectl`, `aws`, …). Those are precisely the shapes the top failing clusters would need
(`Bash(bash:*)`, `Bash(python3:*)`, `Bash(curl -s:*)`). A rule with a positional argument
(`Bash(python3 /Users/chrisren/…:*)`) survives — but it is per-path and buys nothing on a corpus of
one-off scripts.

**Verdict on question (d): there is no top-cluster `Bash(prefix:*)` rule worth adding.** The
clusters that carry the hours are either behind the pre-gate (3a) or in the drop list (3b), and the
ones that are neither already match — `cc-permission-audit` measures **63.1% of 54,906 Bash
invocations already match an allow rule**. The rules that must *stay* prompts are the five in §1c
plus `AskUserQuestion` (117 prompts, deliberate).

---

## 4. What the decider actually clears today — 5.4%

Replay of every 30-day Bash prompt through the live `hooks/lib/smart-bash-allowlist.py`
`decide()` (offline, no settings touched — `/private/tmp/.../scratchpad/replay.py`):

```
ALLOW=157  DEFER=2748  total=2905          (5.4% cleared)
allow_blocked_hours=3.5  defer_blocked_hours=1037.9      (0.3% of the hours cleared)
allow_slow(>300s)=7      defer_slow=425
--- defer reasons ---
2153 segment not on the allowlist
 292 inside a substitution
 161 segment is behind the operator's own gate
 133 could not decompose the command with confidence
   6 danger pattern
   3 unterminated heredoc
```

Failing segment verbs, one count per command, weighted by the hours their commands blocked
(`replay2.py`):

| verb | commands | of which >5 min | Σ blocked h |
|---|---:|---:|---:|
| curl | 1,421 | 46 | 117.9 |
| **rm** | **660** | **193** | **428.0** |
| **git** (not fence-crossing) | **378** | **154** | **345.3** |
| python3 | 344 | 38 | 103.1 |
| bash | 165 | 72 | 177.2 |
| cp | 160 | 48 | 90.5 |
| cat | 129 | 30 | 79.4 |
| sed | 87 | 23 | 58.0 |
| printf | 83 | 31 | 49.2 |
| tar | 58 | 23 | 57.6 |
| timeout | 54 | 18 | 36.0 |

`curl` is the biggest *count* and one of the smallest *costs* per unit — and it is concentrated:
563 of its prompts came from one session on one day (`73ace584`, 2026-08-24), 262 from another
(`28b30953`, 2026-08-21). It is a burst from web-research sessions hitting one-off domains, not a
recurring shape a rule could cover. **Rank by hours, not by count.**

### 4a. Three named parser defects, ~260 blocked hours

Probed directly against the live module (`/private/tmp/.../scratchpad/probe.py`, `probe2.py`):

**D1 — `mktemp` is on no whitelist, so every command that allocates a scratch dir defers.**
```
'T=$(mktemp -d); echo hi > "$T/f"; rm -rf "$T"'  → defer: inside a substitution: segment not on the allowlist: mktemp -d
```
292 commands in 30 days defer on `inside a substitution`. `mktemp` creates a directory under
`TMPDIR` and prints its name; it mutates nothing a caller names.

**D2 — a variable target can never be judged, so the whole scratch-teardown family defers.**
```
'rm -rf "$T"'  → fence=None  allowed=None
```
Top failing `rm` shapes, all of them a variable assigned from `mktemp -d` earlier in the *same
command*: `rm -rf "$T"` 79 cmds / 46.3 h · `"$D"` 30 / 63.8 h · `"$d"` 18 / 23.4 h · `$T` 17 /
3.1 h · `"$P"` 11 / 19.5 h · `"$WT"` 8 / 14.0 h · `"$PRE"` 3 / 25.1 h — **~234 commands, ~180 h.**
The decider has no intra-command variable tracking.

**D3 — `git -C <path>` is unhandled: the same subcommand allows bare and defers with `-C`.**
```
'git log --oneline -5'                              → ALLOW  (git log: read-only)
'git -C /Users/chrisren/Development/… log --oneline -5' → defer (segment not on the allowlist)
```
`git -C "$R"` 15 cmds / 49.6 h · `git -C /Users/…/claude-infrastructure` 7 / 17.7 h · `git -C .`
3 / 12.0 h · `git -C $W` 3 / 0.6 h — **28 commands, ~80 h**, entirely because `verb()` reads `-C`
as the subcommand.

**D4 — `load_fence()` collapses two rule types into one, and the literal `deny` rules over-fence.**
```
'rm -rf /tmp/x'  → fence='rm -rf /'   (but: allowed_segment says "rm-safe-allowlist would allow this target standing alone")
'rm -f  /tmp/x'  → fence=None         (clears)
```
`load_fence()` strips a trailing `:*` and stores everything else as a **prefix**, then
`crosses_fence()` tests `seg.startswith(p)`. The matcher-truth doc establishes the harness's own
semantics: `<x>` ending in `:*` is a *prefix* rule, everything else is an **exact literal**. So
`Bash(rm -rf /)` — written to stop root deletion — fences every absolute-path `rm -rf` on the box,
including the scratch paths `hooks/rm-safe-allowlist.sh` exists to clear. The docstring calls the
generosity deliberate; the cost is that the rm-safe hook is unreachable through the decider for any
`-rf` target under `/tmp`.

**Failure direction of D1–D4:** all four currently err *toward prompting* — they are silent-and-safe,
loud-and-expensive. Fixing them moves the failure direction toward **allow**, and a `PreToolUse`
allow bypasses the permission system completely (`hooks/model-permission-decider.py:39-41`, measured
2026-08-12: an `allow` "sailed past the allowed-working-directory write guard"). D3 is the one with
essentially no exposure (a path argument cannot make a read-only git subcommand mutating). D1 is
near-zero. D2 needs a hard precondition — allow only when the variable has exactly one assignment in
the command and it is a literal `$(mktemp -d)`. D4 is a *correction toward the harness's real
semantics*, not a loosening, but it is the one that touches a `deny` rule and should ship with a
bats case that keeps `rm -rf /` itself fenced.

---

## 5. The loop: producer → proposal → application

### 5a. There is no loop. Every stage is stalled, and I measured the stall.

| stage | artifact | state |
|---|---|---|
| producer | `bin/cc-permission-audit` (landed 2026-07-30, `d45ab538b`) | **no scheduler.** `grep -rl cc-permission-audit` over the repo: 7 docs, 1 hook comment, 0 plists, 0 `scripts/launchd/`. ~40 invocations across 50 days of `bash-commands.log`, nearly all inside its own bats suite or piped to `head`. |
| producer (2) | built-in `/fewer-permission-prompts` skill | Contract (verbatim from the skill roster): *"Scan your transcripts for common **read-only** Bash and MCP tool calls, then add a prioritized allowlist to **project** `.claude/settings.json`."* Aimed at the wrong stratum on this box: read-only single commands are already 63.1% covered; the blocking population is 43.7% pre-gated and 90.4% compound. |
| proposal | — | none exists. `cc-permission-audit` prints a ranked list to a terminal; nothing persists it. |
| application (settings) | `permissions.allow` | **operator-gated.** `migrations/README.md:68-78`: a migration touching `settings.json` declares `c10` — staged, never run, filed to `cc-backlog needs`. The C10 rescope (*"operator can revert"* replacing *"operator runs"*) **has not been ratified**, so the runner does not self-authorise. `grep -l permissions migrations/*.sh` → zero. |
| application (hook) | `hooks/lib/smart-bash-allowlist.py` | **agent-drivable.** Ordinary repo work: lands via the project `/ship`, goes live on the per-file symlink. It was rewritten wholesale on 2026-08-20 by an agent and landed. |
| escalation | `scripts/lead-supervisor.sh:571` `⛔ PERMISSION-PENDING` page | fires (5,117 IDL records today) — but see 5c. |
| operator drain | rows `c0e7b1128788` (2026-09-06, 8 sessions), `8365f6c8b37e` (2026-09-08 07:04, 9 sessions) | both `status: blocked`, both still open. Each ships a `--run` script that *navigates* panes and grants nothing. |
| prune | row `7d5d083cb7b0` (2026-08-17) | `blocked` 22 days. 245 provably-redundant approved patterns across 10 files still live. |
| audit-vs-drop-list | row `78b76e1a8311` (2026-08-21) | **discharged by §3b of this document.** |

### 5b. The producer is itself classifier-denied — measured in this session

```
$ cd /tmp && timeout 300 /Users/…/exhaustive-drive/bin/cc-permission-audit --prune
Permission for this action was denied by the Claude Code auto mode classifier.
Reason: Blocked by classifier.
```

Recorded as row 27 of `~/.claude/logs/permission-denied.jsonl` at `2026-09-08T21:52:57Z`. The
command is documented dry-run-by-default and *writes nothing* without `CONFIRM=1`, but it walks
every `~/.claude*/settings.json` and its flag is spelled `--prune` — squarely inside the
`Self-Modification` soft-deny (*"Modifying the agent's own configuration, settings, or permission
files"*). The plain report form (`cc-permission-audit 30`) ran without a prompt, and importing
`auto_mode_dropped()` as a module ran without a prompt. **A producer whose canonical invocation is
refused cannot close a loop.**

### 5c. The escalation path pages into a box nobody drains

`scripts/lead-supervisor.sh:355-359`, verbatim:

> Consequence: a session sat blocked on a permission prompt for 15.2 hours while every page was
> recorded as SENT into a box holding 997 unacked messages that no drain would ever run.

That specific liar was fixed (the function now parses `cc-notify`'s `verdict=` token). The
volume is not: **5,117 `permission_pending` records in 13.4 h over 22 sessions** is roughly one
record every 9 seconds. An alarm at that rate is an alarm that says as little as one that never
fires (memory: `alarm-polarity-and-attention-budget`). The two operator drain rows sat unrun for 2
days and 15 hours respectively.

### 5d. The refusal ledger records no cause

All 27 rows of `permission-denied.jsonl` carry `reason` ∈ {`"Blocked by classifier"` (24),
`"Stage 2 classifier error - blocking based on stage 1 assessment"` (3)}. The header
(`hooks/permission-denied.sh:36-38`) predicted *"the classifier's own prose sentence, not a code"*;
what the harness actually ships on this event is a bare category-free string. **Nothing downstream
can cluster denials by soft-deny cause.** The prose *is* available — on the `is_error` channel of
the `tool_result`, which is where `permission-matcher-truth-2026-08-20.md` had to go to read
refusals at all. Note also the ledger is one day old (landed `426d5da66`, 2026-09-07): 26 rows in
its first ~19 h, of which 23 are `Bash`, and the top shape is `kill <pid>` (4 rows) — the
auto-mode classifier refusing to end a parked watcher, which memory already indexes as
`auto-mode-classifier-denies-acting-on-a-live-session`.

### 5e. The loop that would work

```
  lead-supervisor tick (already runs)                       ← producer, already scheduled
      └─ beacon archive + permission-denied.jsonl
             └─ replay through smart-bash-allowlist.decide() ← the residual, computed not guessed
                    └─ docs/research/permission-residual.jsonl  ← PROPOSAL (ranked by Σ blocked hours)
                           ├─ decider change  → ordinary repo work → /ship   [AGENT-DRIVABLE]
                           └─ settings change → c10 migration → cc-backlog needs [OPERATOR]
```

The routing rule is the load-bearing part: **a proposal that widens `hooks/lib/smart-bash-allowlist.py`
is agent work; a proposal that widens `permissions.allow` is a c10 migration.** §3 says almost every
worthwhile proposal is the first kind, so the operator-gated branch should be nearly empty — which is
what makes the loop closable at all. Every widening ships with a bats case proving the fence still
holds on a **compound** form; that is the 2026-08-20 lesson, whose suite went green because every
case it tried was a single command.

---

## 6. Adversarial pass — what I checked because a hostile reviewer would

1. **"Your `waited_s` is the time to the session's next tool call, not the block."** Checked: 89%
   attributable in the decidable subsample (§1a), and corroborated by a wholly separate instrument
   (supervisor IDL, §1b) that measures age-at-sweep and never touches `waited_s`. Both land on
   ~6 permanently-blocked sessions.
2. **"Your <10 s bucket is the operator answering fast, so the classifier story is invented."**
   Refuted by hour-of-day: 170 fast resolutions at 04:00 and 108 at 02:00 local (§1c).
3. **"Auto mode drops Bash allow rules, so §3b's whole recommendation is moot / or: it drops
   nothing, so your rule advice is wrong."** Neither. Measured 7/339 per config dir, 2.1% fleet,
   `classifyAllShell=false` — narrow, but biting exactly the bare/flag forms the big clusters need.
   I had drafted the stronger, wrong claim before running it.
4. **"70.3% pre-gated."** My own first number, and I discarded it: the subshell arm was matching
   parentheses inside quoted URLs and User-Agent strings. 43.7% is the floor that survives
   inspection.
5. **"`curl` is 49% of prompts, why isn't it recommendation #1?"** Because it is 10% of the hours
   and 60% of its prompts come from two sessions on two days. Ranking by count would have written
   a rule for a burst.
6. **Not checked (named gap):** whether a `PreToolUse` `ask` verdict from
   `model-permission-decider.py` genuinely survives auto mode *on 2.1.260*. The measurement in its
   header is on 2.1.220 and is now 27 versions old; `error-wording-drifts-between-versions` applies
   to behaviour too. Re-measure before arming shadow mode.
7. **Not measured:** the 117 `AskUserQuestion` prompts. They are deliberate and out of scope for an
   allowlist, but they are 3.8% of the population and I did not price their block time.

---

## 7. Recommendations, with failure direction

| # | change | conviction | effort | errs toward |
|---|---|---:|---|---|
| R1 | Teach `verb()` to skip `git -C <path>` (and `--git-dir`/`--work-tree`) before reading the subcommand | 93% | S | allow — but only for subcommands already whitelisted read-only |
| R2 | Add `mktemp`/`mktemp -d` to the read-only set so `$(mktemp -d)` stops poisoning the substitution pass | 91% | S | allow — mutates nothing a caller names |
| R3 | Split `load_fence()` into prefix rules (`:*`) and exact literals, matching the harness's own semantics, so `Bash(rm -rf /)` stops fencing `rm -rf /tmp/x` | 88% | S | allow — ship with a bats case that keeps `rm -rf /` and `rm -rf ~` fenced |
| R4 | Track single-assignment `VAR=$(mktemp -d)` within a command and resolve `$VAR` to a scratch root for the `rm` path | 79% | M | allow — hard-gate on exactly one literal assignment, no reassignment, no suffix that escapes the root |
| R5 | Persist `cc-permission-audit`'s ranked residual as a proposals file on the supervisor tick, and route decider proposals to `/ship` and settings proposals to a c10 migration | 84% | M | more allows landing without an operator read — mitigate with the mandatory compound-form bats case |
| R6 | Do **not** add `Bash(prefix:*)` rules for the top clusters | 90% | — | inert work + an operator-gated c10 for no measurable benefit |
| R7 | Give `permission-denied.sh` the classifier prose (from the `tool_result` `is_error` channel) so denials can be clustered by soft-deny category | 76% | M | more log volume; today it is silent in the state that matters |
| R8 | Arm `hooks/model-permission-decider.py` in **shadow** mode (row `7cdf4ea8f10e`) — the only lever that reaches the 43.7% pre-gate stratum — after re-measuring its 2.1.220 assumptions on 2.1.260 | 71% | M | shadow errs toward zero effect; the eventual `enforce` errs fail-open, which is why shadow first |
| R9 | Fix the producer's own denial: have the loop import `auto_mode_dropped()` rather than shelling `cc-permission-audit --prune`, or rename the read path | 87% | S | the read path becomes callable; the `CONFIRM=1` write path stays operator-only |

**Expected recovery if R1–R4 land:** ~260 of the 1,040–1,172 blocked hours (25%), from
`git -C` (~80 h), the `mktemp`/`rm -rf "$VAR"` family (~180 h). That leaves the pre-gate stratum
(43.7% of commands, ~773 h by the loose union / ~500 h by the strict one) reachable only by R8.

**The one thing that is not a recommendation:** the five `permissions.ask` rules and the 322 prompts
they raised are the system working. Any proposal that clears them is the defect, not the fix.

---

## Sources

- `~/.claude/autonomy/permission-archive/*.jsonl` (3,832 rows; 3,046 in 30 d) — `hooks/cc-permission-beacon.sh`
- `~/.claude/logs/permission-denied.jsonl` (27 rows, 2026-09-08 only) — `hooks/permission-denied.sh` (landed `426d5da66`, 2026-09-07)
- `~/.claude/autonomy/idl.jsonl` — 5,117 `permission_pending` records, 22 sessions, 13.4 h
- `~/.claude/logs/bash-commands.log{,.*.gz}` — the denominator
- `/tmp/cc-permission-pending/` — 4 live beacons at 16:47 local
- `hooks/lib/smart-bash-allowlist.py` (39,257 B), `hooks/smart-bash-allowlist.sh`, `hooks/model-permission-decider.py`, `hooks/rm-safe-allowlist.sh`, `hooks/notify.sh:221`, `scripts/lead-supervisor.sh:110-122,350-359,507-581`
- `bin/cc-permission-audit` (`_classify` at :161, `auto_mode_dropped` at :445), `bin/cc-queue`, `bin/cc-blockers:1086-1109`
- `migrations/README.md:34-88` (the c10 contract)
- Prior work built on, not redone: `docs/research/permission-prompts-2026-08-20.md`,
  `docs/research/permission-matcher-truth-2026-08-20.md`, `docs/parks/78b76e1a8311.md`
- Backlog: `78b76e1a8311` (discharged here), `7d5d083cb7b0`, `ce5e5310c457`, `7cdf4ea8f10e`, `8365f6c8b37e`, `c0e7b1128788`
- Replay scripts (scratchpad, disposable): `replay.py`, `replay2.py`, `replay3.py`, `probe.py`, `probe2.py`, `pregate2.py`, `drop.py` under
  `/private/tmp/claude-501/-Users-chrisren-Development-claude-infrastructure/b418b97a-d3ec-4444-b993-4f29d55f425a/scratchpad/`
