# The hold was already over — and its decider is refuted on the binary we are running

**Backlog row:** `b69b1d957cec` — *"STANDING WATCH — Claude Code binary advance past 2.1.220,
currently HELD."*
**Venue:** local worktree `wt-b69b1d957cec`, dispatched 2026-09-08. **Skill:** `cc-version-audit`.
**Disposition:** premise REFUTED on both halves — the hold is not in force, and the blocker that
justified it is not present in the code.

---

## 1. Provenance of every reading below

Checked before acting, per the brief's first step:

| Read | Result |
|---|---|
| `rev-parse --is-shallow-repository` (shared checkout **and** this worktree) | `false` — no depth-50 horizon; ancestry reads are sound |
| `git rev-list --count HEAD..origin/main` | 5 behind at intake → fast-forwarded → **0** |
| `git rev-parse origin/main:bin/cc-dispatch` | `b4e8edb92e17…` — **EQUAL** to the brief's composing blob. The dispatcher that fired this session IS trunk; landed is live on this path. |

## 2. The premise is false: we have not been on 2.1.220 since 2026-09-03

The row, the `2.1.228` MANIFEST entry, and the `2.1.237` band assessment all describe a system held
at 2.1.220. **This session is running 2.1.260.** Step 0 of the skill exists precisely because
`claude --version` cannot see this; all three independent readings agree:

```
ps -o command= -p $PPID → /Users/chrisren/.claude-260/node_modules/.bin/claude …
CLAUDE_CODE_EXECPATH   → …/.claude-260/…/bin/claude.exe
AI_AGENT               → claude-code_2-1-260_agent
~/.zshrc:496           → local _bin="$HOME/.claude-260/node_modules/.bin/claude"
~/.claude-260 mtime    → 2026-09-03 19:52
```

The advance was deliberate, not an escaped auto-install: it rode the Fable 5.1 frontier flip, and
`docs/research/frontier-track-gate-2026-09-04.md` §3 already states in passing *"the live launcher
`claude` is on 2.1.260"*. **What did not happen is the ledger write.** `MANIFEST.jsonl`'s last entry
is `2.1.237`, dated 2026-08-20 and itself a changelog-only partial audit whose notes say the
adversarial sweep "was NOT run". So for five days the SSOT ledger, the standing-watch row, and the
running system disagreed, and nothing was positioned to notice — the row's own revisit trigger could
only ever be evaluated by a session that read the row, and reading the row told you the wrong version.

This is the failure the skill's own header warns about, one level up: *a runbook that restates a
perishable fact has no path to learn it changed.* Here it was not the runbook but the **work item**
that restated it. A standing watch whose trigger is phrased against a version number goes stale the
moment someone advances the version for an unrelated reason.

## 3. The decider (#84974) is not present in 2.1.260 — measured, not inferred

The hold rested on one thing: 2.1.224 removed the 200-subagent-per-session cap, leaving
`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` as the sole runaway bound, and GH #84974 said that variable
did not actually disable nesting. The row's release condition (a) was *"a release fixes #84974 or
restores a spawn ceiling."*

**GitHub cannot answer this.** #84974 is still OPEN (read 2026-09-08), as are #85264, #85015, #84224
and #85154 — but an open issue is a statement about a tracker's hygiene, not about a binary. So the
question was put to the binary itself. Extracted from
`~/.claude-260/…/bin/claude.exe` (198 MB Bun SEA), the Agent tool's spawn path reads:

```js
let de = ac(n.agentContext);        // current depth
let be = $S();                      // resolved max
if (de >= be) throw p("subagent_launch","subagent_depth_cap"),
  … new JT(`Subagent nesting limit reached (depth ${de} of ${be}). …
            ask them to raise CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH.`);
```

and the resolver, one chunk over:

```js
var o = 3, _ = "tengu_hazel_trellis";
function $S(){
  let n = a.CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH;
  if (n !== void 0) return n;                       // ← env branch: returned RAW, unvalidated
  let t = Ci();
  if (t.maxSubagentSpawnDepthFromGrowthBook === void 0) {
    let e = getFeatureValue_CACHED_MAY_BE_STALE(_, o);
    t.maxSubagentSpawnDepthFromGrowthBook =
      (typeof e === "number" && Number.isInteger(e) && e >= 1) ? e : o;   // ← flag branch: validated
  }
  return t.maxSubagentSpawnDepthFromGrowthBook;
}
```

The root is 0-based — confirmed independently by **#85264's own attached metadata**, where a
directly-dispatched fork records `"spawnDepth":1` and the unauthorized nested one records
`"spawnDepth":2`. So with our `=1`, a level-1 subagent evaluates `1 >= 1` and is **refused**.
Nesting is flat. Executing the comparison across the value space:

```
MAX="1"     depth0(main)=ALLOWED  depth1(sub)=REFUSED   ← our configuration: contained
MAX="3"     depth0=ALLOWED        depth1=ALLOWED        ← the default when unset
MAX="abc"   depth0=ALLOWED        depth1=ALLOWED  depth2=ALLOWED
```

**Condition (a) is therefore discharged on the merits**: whatever the tracker says, the off-by-one
is not in the code path we execute. 2.1.220 reads `>=` as well, so the regression lived in the
2.1.222–2.1.225 window #84974 describes and has since been restored.

### 3a. What the audit found that the row could not have known — the env branch fails OPEN

The two branches of `$S()` are not held to the same standard. The GrowthBook branch validates
integer-ness and floors at 1; **the env branch returns whatever the environment holds, unparsed.**
A non-numeric value yields `NaN`, every `de >= NaN` is false, and the guard admits at *every* depth —
silently, with no error and no log. A typo in the one variable that is now the sole runaway bound
disables it completely, and the failure presents as normal operation.

Our `~/.zshrc:496` pins `=1` correctly, so nothing is currently wrong. The exposure is that nothing
was *checking*: `check06_depth.sh` verifies the variable is **delivered** to the binary, which is a
different claim from the binary **containing** anything — and #84974 is the standing proof that the
two come apart, since on 2.1.225 delivery was correct and nesting ran anyway. A delivery-only probe
reports PASS across that entire regression window.

**Cure:** `lib/cc-upgrade-gate/check15_depth_effect.sh` (this diff) reads the candidate binary's own
comparison operator and fails on the exclusive `>` form. Red-proofed four ways in
`tests/cc-upgrade-gate.bats`: the pre-fix `>` shape goes FAIL, `>=` goes PASS, a marker-less stub
SKIPs rather than greening, and an unreadable comparison fails closed. A fifth case pins the defect
found while building it — a SEA carries each anchor many times, so scanning only the first match
reads the constant pool and reports UNKNOWN on a healthy build.

Two residual facts worth carrying, neither actionable today: the default when the variable is unset
is **3**, and it is **remote-flag fed** (`tengu_hazel_trellis`), so any spawn path that does not
inherit our launcher env is at 3 and server-adjustable. And the 200-per-session ceiling is still
gone — `recordRefused("depth_limit")` is the only refusal class in the spawn path, so depth remains
the only bound.

## 4. The band 2.1.238–2.1.263 is heavily net-positive for this box's specific shape

Read from the version we actually run (Step 2's slice floor), not from `latest` minus a few.

**Memory cluster — seven fixes, and one of them names #85015's own hypothesis.** #85015 (our filing:
two workers at 26.4 + 20.3 GiB froze this 16 GB machine) speculated the leak was *"accumulated
Bash/WebFetch output no longer reachable from the conversation context."* 2.1.239 shipped *"Fixed
WebFetch retaining expired page content in memory for the whole session instead of the intended 15
minutes."* Alongside: 2.1.238 released subagent tool results leaving the display window; 2.1.243 cut
40–70 MB/session and made the runtime GC sooner; 2.1.246 fixed transcript-view retention and a Write
OOM; 2.1.247 fixed unbounded growth when a hook or background task's output file is unwritable;
2.1.257 fixed unbounded growth on non-JSONL piped input. **Churn floor = 2.1.257** (Step 4: the last
fix in the cluster, not the first clean-looking version). We are above it.

**Symlink and deletion cluster — this box is the exact shape these fixes describe.** `~/.claude` is
per-file symlinks into a git checkout, which the skill flags as a standing blocker class. 2.1.247:
*"Fixed the Bash sandbox's after-command cleanup deleting a dotfile-managed `~/.claude/settings.json`
symlink … when it is repointed outside the sandbox's writable area."* Also 2.1.251 (file tools
following a symlink swapped after the permission check — a TOCTOU), 2.1.251 (Grep/Glob ignoring
`Read()` denies through a symlinked search path), 2.1.257 (plugin component paths escaping via
symlink), 2.1.239 (`claudeMdExcludes` not excluding a symlinked `.claude/rules`). Cluster floor
2.1.257; we are above it.

**The zsh permission-bypass class recurred and was fixed in the version we run.** 2.1.221's `[[ ]]`
hidden-command bypass had a sibling: 2.1.260 *"Fixed Bash permission checks auto-approving zsh
commands that hide a command substitution in a REPORTTIME, REPORTMEMORY or DIRSTACKSIZE
assignment."* Our Bash tool calls are zsh, so this is a live surface, and 2.1.260 is the fix.

**Worktree safety**: 2.1.248 *"the background session now holds the worktree's lock while it runs,
so cleanup and `git worktree remove` leave it alone"* — the 2.1.222 concern, further hardened.

**One containment REMOVAL, in 2.1.260 itself** — the standing caution this audit adds: *"Removed the
one-hour time limit on background commands started by subagents; they now run until they exit or are
stopped."* On an autonomous fan-out box a runaway background command from a subagent now has no time
bound. Not a blocker (the admission gate and `cc-await-ping` bound the session layer, not this), but
it belongs in the next audit's held-open list.

## 5. Conditions (b) and (c)

**(b) "≥1wk as npm latest" is the unsatisfiable bar the skill already documents** — only two versions
have ever held `latest` for ≥7 days and one of them is our own 2.1.220, which managed it only through
a shipping pause; the longest ordinary tenure in the last 40 releases is 2.99 d against a release
every ~1.5 days. Read as the predicate it intended, **age since publish**: 2.1.260 published
2026-09-03 22:32Z = **4.3 days**. Short of seven — but the bar is now retrospective rather than
prospective, because those 4.3 days were served *on this box, in production*, which is evidence a
hold could never have bought.

**(c) The installer regressions do not reach us.** #84224 (open, and labelled **reproduced** by
maintainers) and #85154 (open, labelled `stale` — inactivity, not a fix) both live in the
**auto-updater** path. Two independent guards keep this box off it, both verified this session:
`DISABLE_AUTOUPDATER=1` exported at `~/bin/claude-latest:342`, and the MANIFEST allow-list at
`:181-219` which default-denies any version not explicitly marked `stable`/`candidate`. Our installs
are manual `npm install --prefix ~/.claude-NNN`. Neither issue has a path to this machine.

## 6. Verdict

**CONFIRM 2.1.260 on the eval/live track. Do not chase 2.1.263.**

The hold is discharged: (a) on the merits, by measurement; (b) as re-read against the predicate the
skill says it always meant; (c) by two guards that make the cited mechanism unreachable here. And
the band is not a neutral advance — it carries the memory cluster that names our own OOM filing's
hypothesis, the symlink-cleanup fix for our exact `~/.claude` shape, and a zsh permission bypass in
the same class as the one the hold was forgoing.

2.1.263 is 2.2 days old and its entire changelog is *"Bug fixes and reliability improvements."*
There is nothing in it to buy and no way to read what it changed. 2.1.261's additions
(`bashOutputMaxChars`, `/skill-doctor`, an `rm -rf` prompt hardening) are real but not load-bearing.
Staying put is the position with evidence behind it.

**Stable track is unchanged at 2.1.114** and nothing here proposes moving it. Every MANIFEST entry
written by this audit is `status:"skip"` — deliberately, because MANIFEST governs the
`claude-latest` **stable** launcher and `candidate` there would auto-install over the 2.1.114 pin.
That is the trap five prior entries document; `skip` is both the correct verdict and the safe
direction.

## 7. What the next audit inherits

The row's revisit trigger should not be re-armed in its old form. Replace the version-keyed phrasing
with the two things that are actually checkable, and let the gate carry them:

1. **`scripts/cc-upgrade-gate.sh <bin> <model>` now answers the containment question directly** —
   #6 for delivery, #15 for effect. A future off-by-one goes red without anyone re-reading a tracker.
2. **Held open, carried forward:** the 200-per-session ceiling is still absent; the depth default is
   3 and remote-flag fed; the env branch fails open on a malformed value; subagent background
   commands lost their one-hour bound in 2.1.260; #84974 / #85264 / #85015 / #84224 / #85154 all
   remain open upstream regardless of the code's current state.
