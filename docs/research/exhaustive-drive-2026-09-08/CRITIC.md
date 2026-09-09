# CRITIC — completeness review of the 12-axis wave (2026-09-08)

Role: completeness critic over A01–A12 + their skeptic passes + LEAD-NOTES. Question: what does the
operator's 7-step workflow need that no report covers; which claims were never verified; which
sources the question required that nobody opened; where do two axes contradict each other.
Read-only; the only file written is this one. Every number below says "measured" (I ran the command,
shown) or "inferred". Times are 2026-09-08 UTC unless noted; live stores were read 23:50Z–00:20Z
(i.e. ~2–7 h after the axes), so live counts differ from theirs by drift, and I say so where it matters.

---

## 0. The one thing the wave did not measure, and it is the denominator of everything else

**Sessions on this box mostly do not end at a Stop. They end inside a Bash tool call that retires
the pane.** Ten of the twelve axes study Stop-time mechanisms (hooks, /goal, caps, close text). The
population those mechanisms can ever see is the sessions that reach a Stop. Measured today:

```
main-chain transcripts touched today (4 roots, realpath-deduped, agent-*/subagents excluded): 141
dead (beat pid gone, ~/.claude/cc-beats/<sid>.json + kill -0):                                108
  last conversational record = assistant end_turn (reached a clean Stop)                       26  (24%)
  last conversational record = tool_use / tool_result / human prompt / hook block (no Stop)    82  (76%)
    of those 82/83, the last tool call was:
      handoff-fire.sh self-close                                                              43
      handoff-fire.sh --recycle                                                                7
      scripts/drain-recycle-fire.sh (a --recycle wrapper; 4 --recycle sites in the script)    11
      -> deliberate in-tool-call retirement                                                   61  (73% of non-Stop ends)
      an ordinary command (frozen / killed / limit)                                          ~22
  mid-turn dead that carried a >300 s permission prompt today: 22 (14 of them >1 h)
```
Command: python over `~/.claude*/projects/*/*.jsonl` (mtime ≥ 2026-09-08T00:00Z, not `agent-*`, not
`/subagents/`), tail 1.5 MB per file, last record with `type ∈ {assistant,user}` and `isSidechain≠true`,
then the last `tool_use` block; liveness from the beat store's pid; permission joins from
`~/.claude/autonomy/permission-archive/*.jsonl` (`session_id`, `waited_s`, `ts`).

Consequences no axis drew:

1. **The Stop chain (A01, A02, A07, A08, A09, A12) governs ≤ 24 % of session terminations today.**
   `completion-assert`, the SAFE-TO-CLOSE certificate, `session-continue`'s floors, `anti-deference`,
   `dispatch-assert` — none runs on a `self-close`. The last Stop they saw was the previous turn.
2. **The self-close path has no ledger gate.** `scripts/handoff-fire.sh` references neither
   `wrap-ledger` nor `completion-assert` as a gate (`grep -n -E 'wrap-ledger|completion-assert'` →
   one comment at :3282); its refusals are: dirty tree (:7003 "refusing self-close: dirty git tree"),
   live Agent-tool subagents (header :184, exit 4), `--source-pane` argument shape (:6357–6387),
   custody hand-off (`--dirty-owner successor`, :6468). It does **not** check unlanded commits (📦),
   the frozen-DoD remainder, open class-C packets, or the goal. The seven `SessionEnd` hooks
   (`session-end.sh`, `session-deregister.sh`, `session-index-end.sh`, `session-save-id.sh`,
   `harvest-skill-end.sh`, `live-session-registry.sh`, `cc-permission-beacon.sh clear` — `jq
   '.hooks.SessionEnd' ~/.claude/settings.json`) contain no close assertion (`grep -c
   'wrap-ledger|completion|rung|unlanded|dirty'` → 0 for all five scripts). **The terminal close of
   56 % of today's dead sessions is audited by nothing.** Fail direction of the status quo: silent in
   the dangerous state — the exact defect the wave was told to find.
3. **A04's headline dissolves into this.** Re-running A04's own selector (`goalsess.json`, newest
   record an unevaluated arm, file idle >24 h): 434 sessions; last conversational record
   `assistant:tool_use` 261 + `user:tool_result` 153 = **414 (95 %) died mid-turn**; last tool call
   `self-close` **155** + `--recycle` **83** = **238 (55 %)** retired themselves inside a tool call.
   Only **69 (16 %)** had a permission prompt after the arm that waited >300 s (39 >1 h; 251.8 h of
   post-arm wait summed). So "67.7 % of goals armed and never evaluated" is mostly "sessions that
   self-close never Stop" — a property of *our* fire chain, not of `/goal`. A04's skeptic found the
   no-Stop denominator (376/640) but not its cause; A05/A09 found the freezes but did not join them
   to A04; the join says freezes are ≤ 1/6 of the no-Stop population.
4. **`--recycle` inherits the goal** (`scripts/handoff-fire.sh:4676-4684`, `CC_RECYCLE_GOAL_INHERIT`
   default 1, `goal_live_for_sid` :4642): the 83 recycled never-evaluated goals were carried to the
   successor, not lost. A04 R6's proposed CLAUDE.md sentence ("survives --resume, not --recycle") is
   therefore half wrong and should read "dies with the process; re-armed by `--recycle` when the
   condition passes pre-arm validation; restored by `--resume`".

**Critic recommendation C-R1 (conviction 88 %, effort M).** Make `handoff-fire.sh self-close` (and
`--recycle`) run `scripts/wrap-ledger.sh --machine` for the retiring sid and refuse — or at minimum
stamp into the successor brief / custody row — on `📦` (unlanded), `REMAINDER≠0`, or `⛔`. The dirty-
tree refusal at :7003 is the template. Files: `scripts/handoff-fire.sh`, `scripts/wrap-ledger.sh`,
`tests/handoff-fire-*.bats`. Fail direction: errs toward REFUSING a legitimate retire (loud — the pane
stays open with the reason printed, and the operator's existing "self-close refuses a dirty tree" rule
already trains the model to clear before closing); a refusal must never SIGKILL. Do not gate on a
ledger that cannot be computed (`SID` unresolvable ⇒ warn, proceed) — A11-skeptic's two-verdicts trap.
Honest limit: a `--recycle` that fails the gate strands a pane that must recycle for context reasons,
so on `📤` the gate should annotate, not refuse.

---

## 1. Coverage map — the operator's 7 steps against the 12 axes

| Step | Covered by | What is still missing |
|---|---|---|
| (1) at every would-be stop, drive follow-ons | A02 (close taxonomy), A07, A08, A09, A01 | The would-be stop that is a **self-close** (§0). Read-only turns naming work (A08 E1, weakened by skeptic to "no arm without a lexical tell"). |
| (2) Shared Task List for 2+ items | A03, A08 E5 | **No live tracker for the enabling flip.** Row `ebe84950e98a` closed `done` 22:14:32Z on the concurrency probe; `CLAUDE_CODE_ENABLE_TODO_TOOLS` unset in 5/5 `settings.json` (measured); no `migrations/*todo*` exists (`ls migrations/` → 0016–0021, none); `cc-backlog list --open` has 0 rows matching `TODO_TOOLS|Task tool|task list|TaskCreate`. A03 R4's *session*-scoped `OPEN_TASKS_MINE` is invisible to the successor — the boundary "shared" exists for — and nobody connected it to the cross-session key the fleet already has (`~/.claude/autonomy/dod/lineage.tsv`, walked by `dod_lineage_ancestors`, found by A01). |
| (3) research exhaustively; "Dynamic Workflows usually optimal" | A06 | The operator's premise is **contested by the wave's own numbers and no axis owned the decision**: A06 quotes Workflow at 1.5–1.7× the quota of a dispatched session per unit (workflows-vs-teams §3c) and its skeptic says A06 "never reconciles". Nobody measured outcome quality of a Workflow vs a subagent wave on a conviction-moving question. Lead §5 settled headless availability (Workflow present under `-p`); **this session (a depth-1 research subagent) has no `Workflow` tool** (measured: absent from my tool list), so a research subagent cannot escalate into one — the venue the operator names is unreachable from the venue the fleet uses for research. |
| (4) ≥90 % convicted → send off | A06 (research verb), A11 (capacity) | The two axes contradict (§3 C1, C2): A06's "capacity is not the constraint" rests on a gate A11 proved blind, and A06's "the dispatcher fires it itself" lands rows in a lane A11 measured at 2.9 rows/h with 65 % real-fire failure. |
| (5) itemized decisions, answer-first, MECE | A08 E3 (refuted: S6 already mandates naming), A06 (packets: 13/31 lack options), A10 (27/28 open class-C author-dead) | No axis measured whether closes holding ≥2 decisions actually present them in S2/S6 today; the only proxy is the packet store (29/31 without conviction). Acceptable — the store-side gate shipped today is the right instrument; note it as unmeasured, not as a hole. |
| (6) stop only after all that | A04 (/goal), A07 (caps), A12 (ProposeGoal) | **The ending that is not a Stop** (§0). Also "succession fidelity" (§2 M2): what survives `/handoff`/`--recycle` — goal (inherited, §0.4), tasks (session-scoped: lost), spool (A11: none exists), DoD (lineage.tsv: kept), per-worktree approvals (§2 M3: deleted with the worktree). No axis measured what a successor loses. |
| (7) run everything runnable; shrink prompts via the allowlist | A05, A09 R1 | **The layer where approvals actually land was never opened** (§2 M3): `.claude/settings.local.json` — 95 rules in the shared checkout, 207 across 21 worktrees, 77 % exact literals that can never match twice, gitignored, deleted by `worktree-gc`. A05 counted only `~/.claude/settings.json` (339). |

---

## 2. Missing axes (measured where I could)

### M1 — Session termination census (§0). Owner: the synthesis; feeds A01, A02, A04, A07, A08, A12.

### M2 — Succession fidelity (what a successor inherits)
No axis measured it. Stores involved and their state per the wave: goal condition — inherited on
`--recycle` (handoff-fire.sh:4676-4684), restored on `--resume` (A12: `tengu_goal_restored_on_resume`);
frozen DoD — repo-keyed with lineage (A01, `hooks/lib/dod-path.sh`); tasks — `OPEN_TASKS_MINE` as
proposed is session-scoped and dies (A03 skeptic); refused-spawn briefs — no spool exists, 20/20
serialized inline (A11 skeptic); permission approvals — per-worktree `settings.local.json`, deleted with
the worktree (M3); open class-C packets — 27 of 28 have a dead author and can never render ⛔ again
(A10). The measurement to run: for today's 18 recycles (handoffs.jsonl `recycle-engaged` 12 +
`recycle-intent` 16; my transcript count 7 + 11), diff predecessor vs successor on each store.
Fail direction of not building it: silent — a lost item looks like a finished one.

### M3 — The approval layer step 7 actually uses (measured)
```
~/Development/claude-infrastructure/.claude/settings.local.json  allow=95  (24 prefix `:*)`, 71 exact literals, 2 compound), mtime Sep 8 12:17
/Users/chrisren/Development/.worktrees/*/.claude/settings.local.json   21 of 201 worktrees; 207 rules; 159 exact literals (77 %)
.gitignore:20  .claude/settings.local.json          (gitignored ⇒ not in any worktree checkout)
.worktreeinclude                                    absent (cat → No such file)
scripts/worktree-gc.sh                               removes via `git worktree remove` (:33) ⇒ the file dies with the worktree
permission-archive record keys                       no field distinguishes "allow once" from "always allow" (13 keys, none about permanence)
```
This is the harness's own "Yes, and don't ask again" path — the mechanism the operator's step 7
describes — and it is (a) per-checkout, so a grant made in a fired worktree never reaches the next
fired worktree, (b) 77 % exact literals (`Bash(shellcheck /tmp/hf-head.sh)`), the "48 % one-shots
that could never match twice" of commit `86e354262`, now worse, (c) invisible to A05, whose 339-rule
census read only the user layer, and to A05's proposed loop. **Critic recommendation C-R2 (conviction
85 %, S/M):** a periodic promoter that reads every `settings.local.json` (shared + worktrees), drops
exact literals, and proposes prefix rules into the committed project `.claude/settings.json` (35 rules,
last touched 2026-08-12) — agent-drivable because the project file is ordinary repo work, unlike the
user layer's c10. Fail direction: errs toward allow-widening without an operator read; bound it to
prefixes that already appear ≥3× as exact approvals, and never touch `permissions.ask/deny`. A12-
skeptic2's finding that `Bash(python3:*)` is a universal escape hatch in the user layer should be
weighed in the same pass.

### M4 — Dynamic Workflows as a venue (step 3)
See coverage row (3). Two measured facts nobody combined: Workflow is offered to 260/260 main sessions
and to headless `-p` (lead §5), and **not to subagents** (this session). A06's cost table says a
Workflow unit costs 1.5–1.7× a dispatched session. The operator's "usually the optimal method" is
therefore either about quality (unmeasured) or false on cost; the synthesis must say which and file
the quality measurement rather than adopt the premise.

### M5 — The IDL premise in the wave brief is wrong, and half the axes inherited it
```
ls ~/.claude/autonomy/idl.jsonl*  → live file 12.7 MB + 8 archives idl.jsonl.<ts>.gz
first ts of the oldest archive (gzcat | head -1 | jq -r .ts): 2026-08-29T09:28:23Z
idl.jsonl.chain (57,194 lines) = "<n>\t<sha256>" per line — a tamper-evidence hash chain, not data
```
Eleven days of IDL exist. A07 and A11 used the archives (A07's jq census then died at line 844,016 —
its skeptic's finding); A01, A02, A04, A08, A09, A10 censused the 13-hour live file and called it
"today" or "the IDL". Every "no rung/hook ever fired" claim from those six is a 13-hour claim. Lead
§7 restates the wrong premise.

### M6 — Fleet PATH heterogeneity (measured)
```
live claude processes: 25;  /opt/homebrew/bin on PATH: 18;  NOT on PATH: 7
  no-homebrew pids: 7631 (kitty, Aug 29), 66521+66566 (aftman/cargo, Aug 29), 52216+53431 (aftman, Sep 5),
                    16212 (kitty, Sep 8 18:25 — the wave LEAD b418b97a), 19603 (kitty, Sep 8 18:55)
timeout: /opt/homebrew/bin/timeout → Cellar/coreutils/9.1 (homebrew-only; NONE in this shell)
jq:      /usr/bin/jq (system — present on every PATH listed)
```
(`bash -c` loop over `ps -E -o command= -p <pid> | grep ^PATH=`; note the zsh `path` variable trap —
my first attempt clobbered PATH and read 24/25 as no-homebrew; re-run in bash.) Consequences:
A01-skeptic's "`timeout` on the PATH of 0/3 live processes ⇒ every `WRAP_*_TIMEOUT_S` knob is dead"
is true for 7/25 sessions (28 %, including the lead), false for 18/25; `_bounded()`
(`scripts/wrap-ledger.sh:713-715`) degrades to unbounded on those 7. The Stop hooks themselves guard
their `timeout` calls (`completion-assert.sh:796`, `notify.sh:20`, `hooks/lib/osa.sh:39`), so the
exposure is unbounded store scans, not hook crashes. A10 R7's diagnosis ("2 uncovered pids because jq
is off PATH", A10:381) is wrong — jq is `/usr/bin/jq` and `/usr/bin` is on both pids' PATH; the cause
of the two beat-less pids is unmeasured (both are long-lived Aug-29/Sep-5 processes).

---

## 3. Contradictions between axes (each needs a synthesis ruling)

**C1 — A06 vs A11 on capacity.** A06:26-27 "capacity is measurably not the constraint. 903 fires
admitted … zero of the refusals were capacity". A11:37-38, 182-188 "handoff-fire's active-concurrency
term is blind in production on 100 % of fires (48 of 48 admits carry `blind: active`)" because the only
`spawn-presence.sh` source sits inside a command substitution (:4995/:5152 vs :5360). A06's evidence
IS the blind gate's output; A11 measured the box at load 155/10 cores with 9–16 mid-turn against a
ceiling of 8 while that gate admitted. A06's skeptic ran the positive control on the `capacity` gate
field (267 evaluated rows) but not on whether the term was computed. **Ruling needed:** A06 R2
(`cc-backlog research` firing more sessions) must land after A11 R3 (un-blind), and A06's "cost is not
the constraint" paragraph must be struck.

**C2 — A06 vs A11 on the dispatcher.** A06 R2: "`open` is already cc-dispatch's fire predicate, so the
implementation wave fires itself with zero new machinery." A11: local queue 137→101 in 12.6 h
(2.9 rows/h), 96/137 still deferred; fixture-corrected real fires 55, launched 19, failed 36 (65 %).
Plus A06-skeptic's project-conf term (36/220 blocked rows can never fire). Both measured; A06's
conclusion does not survive A11's numbers.

**C3 — A07 vs A12 on the harness block cap, and a reconciliation neither stated.** A07:133-138 "Searching
all 6,131 transcripts for `A hook blocked the turn from ending` returns 0 hits — a UI notification, not a
transcript record." A12: raw 36 files/67 lines (skeptic2: 147 lines/53 files), **4–6 genuine
`type:"system"` events** (08-10 ×2, 08-19, 08-26, all "9 consecutive"). A12 is right; A07's population
was 2,125 files not 6,131 with xargs interleaving (its skeptic). Measured on A07's own 311-block chain:
`c262a75c` (wt-sr-zerohuman, binary **2.1.220**, 6.3 MB) holds **317 `Stop hook feedback:` records and
0 override records**, and `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` is set nowhere (grep over 4 settings.json
+ zshrc/zshenv/zprofile → exit 1). A cap of 8 that demonstrably fires elsewhere and a 317-block chain
that never tripped it are only compatible if the counter measures **consecutive blocks without tool
use** — which is exactly what A12 quoted from the docs ("no tool use for several turns in a row") and
did not connect. Inferred; one binary read settles it (does `qd` reset on a tool_use turn?). If so:
A07 R6's "unbounded driver" is the harness's intended semantics, A12 R4 stands, and the cap is a
no-progress bound, not a block-count bound — CLAUDE.md:399/502/888 should say that.

**C4 — Four numbers for the kill-switch, two incompatible remedies.** A07: 140 sessions/30 d with a kill
phrase in the last genuine user message, 125 single-message, 100 writers; A07-skeptic: 30 / 17 / 23,
today 0 of 477; A08: 29 of 3,182 messages (8 d), 26 machine-authored; A08-skeptic: 38 raw, **27 in
`subagents/agent-*.jsonl` files the hook never reads**, 11 readable, and the live IDL shows
`completion-assert` abstained `kill-switch` **1 time in 530 evaluations** (0.19 %). Remedies: A07 R1
(terminal-only regex + ignore the sole record of a single-message session) vs A08 E2 (operator-only
prose + exclude `<task-notification>`/`<teammate-message>` prefixes); A07-skeptic: terminal-only removes
nothing (briefs end in "and stop."), and excluding the brief contradicts `session-continue.sh:250-252`'s
own design ("fire/recycle briefs are genuine instructions TO this session, which SHOULD disarm").
**Ruling needed:** the only oracle that measures what the hook DID is the IDL abstain count; at 0.19 %
per Stop, ship only the one-line brief discipline (never write a kill phrase into a brief) and no regex
change. Note `stop-chain-wave2-2026-09-03/reader.md`'s multi-line-reader fix landed (`bf6385171`,
2026-09-03), so both censuses do match the reader's view of a message — that is not the discrepancy.

**C5 — The closes-vs-evaluations gap has three incompatible explanations and none reproduces.**
A01 §7: "closes ≥08:22Z = 469 = anti-deference evaluations 469, exact identity — fully explained by the
rotation boundary, not timeouts." Lead §3: "17 sessions with 127 closes wrote ZERO anti-deference
records; 104 of those 127 ran on binary 2.1.220." A09: agent-* sidechain files (measure-closes.py
already excludes them — A09-skeptic). A04/A08 skeptics: "untouched". **Measured at ~19:02Z** (main-chain
`stop_reason:end_turn` records ≥08:22Z, not sidechain, vs `hook==anti-deference-nudge` rows in the live
IDL, joined per sid, version from each transcript's header):
```
2.1.260  sessions=128  closes=632  anti_def_rows=542  deficit=90
2.1.220  sessions= 11  closes= 17  anti_def_rows= 16  deficit= 1
sessions with ≥1 close and 0 rows: 8 (all 2.1.260, 9 closes, 1–2-close probe sessions)
```
Neither the identity (649 vs 558, 14 % deficit) nor the 2.1.220 attribution (1 of 91) reproduces at a
later read. The deficit is spread thinly across 2.1.260 sessions (A01-skeptic saw anti-deference sit
below its invocation baseline too). Cause still open; candidates the wave never separated: end_turns
that are not Stop events (queued-message continuations), hooks exiting before `idl_init` (A09 R5's
mechanism was refuted by its skeptic — the only pre-init exit is a FATAL lib load), and the IDL's own
write failures. Caveat: my "close" is `end_turn`, A01's is "turn-final assistant message"; the 8
zero-row sessions are probes.

**C6 — A refuted number propagated as load-bearing.** A01: `wrap-ledger --machine` 14.38 s in
claude-infrastructure → A01-skeptic 2.15–2.55 s (same cwd), 5.35–6.85 s elsewhere, 8.0–8.6 s with 5
concurrent consumers → lead §2/§2a 1.6–2.1 s. A03-skeptic:51 then argues OPEN_TASKS_MINE's Stop-time
observability from "`scripts/wrap-ledger.sh`, which A01 measured at 14.3 s uncached in this repo".
The remaining true statement is A01-skeptic's: the hot terms are `cc-backlog list --blocked/--all` and
`cc-decide list` (4.4 of 5.7 s in reso-web-app), reached only on the clean-tree rungs.

**C7 — Every row-minting recommendation grows the store the Stop hooks scan, and nobody coupled them.**
A02 R4 (~24 rows/day from peer findings), A06 R2/R3 (research rows, `--kind`), A11 R2 (spool
promotion) all add to `~/.claude/autonomy/backlog.jsonl` — 18,570 rows / 7.0 MB (measured), growing
371–697 rows/day (A01-skeptic), read in full by `cc-backlog list` which has **no fold cache or index**
(`grep -n -i 'cache|index' bin/cc-backlog` → one awk helper), forked twice per `wrap-ledger` run plus
`cc-decide list` once, by five Stop hooks concurrently (A01-skeptic's measured single-flight miss).
Ruling: no row-minting recommendation lands before a fold cache (or a "list since ts" index) does.

**C8 — A03 R4 defeats step 2's word "shared".** Session-scoped `OPEN_TASKS_MINE` is invisible across
`/handoff`/`--recycle` (A03 skeptic); list-scoped would fire forever on 66 stale items (A03). The
middle term exists and A01 found it: `dod_lineage_ancestors` over `~/.claude/autonomy/dod/lineage.tsv`
(445 rows) gives the successor chain; a *lineage*-scoped term (tasks created by this sid or any
predecessor in its lineage, still open) is neither always-on nor amnesiac. Nobody proposed it.

**C9 — Three pagers for one wedge, one of them inert, and a fourth proposed.** A10 R4 proposes
BUSY-SUSPECT in operator-readout; A10-skeptic finds `lead-supervisor.sh` already pages `STALL?` (:91,
telemetry age >1,800 s) and `PERMISSION-PENDING` (:113); A05-skeptic finds the permpend escalation
ladder (commit `10348ff6a`, on trunk) has produced **0** `permission_pending_escalate` records because
the daemon (pid 31716, started 15:17Z) predates the checkout advance — landed, not running. The fix is
a version-asserting daemon reload (memory: registration-precondition-must-assert-version), not a new
alarm; A10 and A05 never cite each other.

**C10 — `ENABLE_STOP_REVIEW` has three verdicts that are all simultaneously true, and the synthesis must
carry all three.** Lead §6 and A01/A04/A07/A12 axes: 0 occurrences in the binary ⇒ "dead setting".
A12-skeptic2: it is the gate of the **security-guidance plugin**'s Stop review
(`…/security-guidance/2.0.7/hooks/security_reminder_hook.py:162,:1910`), set deliberately (backlog
`022683ab85f3`, 2026-07-29: multi-agent worktrees break its diff review). My check: the plugin is
**installed** (`installed_plugins.json`, installPath under `.claude-secondary`, lastUpdated today
18:28Z) but **not in `enabledPlugins` of any of the four `settings.json`** (each lists only
`swift-lsp:false`, tertiary also `frontend-design:true`); its log ends 2026-07-30. So: inert today,
load-bearing the moment the plugin is enabled (its Stop hook carries `asyncRewake:true` — a Stop hook
that re-wakes the session), and deliberately set. A12 R1 (delete it) stays refuted; the row to file is
"plugin installed-not-enabled; `ENABLE_STOP_REVIEW=0` is its safety; document in the env block".

**C11 — "cc-permission-audit has never been run"** (A05 §producer, A08 E8) vs A08-skeptic: the beacon
header records a run ("approved 0 · unknown 3359 over 3,763 prompts" — an instrument artifact,
`join-key-never-populated`). A05's own "~40 lifetime invocations … nearly all inside its own bats
suite" already contradicted "never".

**C12 — Step 2's tracker vanished mid-wave.** A03 R7 "close `ebe84950e98a`" — the lead had already closed
it (22:14:32Z) on the concurrency probe. Nothing replaced it: no migration, env unset in 5/5 dirs, no
open row (measured, coverage row 2). A closed row for a flip that never happened is the
`filed-blocker-is-never-revalidated` trap inverted.

**C13 — A04 R3 vs the uncited prior doc.** A04 R3 (91 %) would reframe `--goal` away from the drive
lever; `docs/research/goal-condition-best-practice-2026-08-09.md` is titled "…why `--goal` has to be
the DEFAULT" and CLAUDE.md § Agent Teams mandates it. A04 cites neither; its skeptic cut R3 to 55 %.
With §0's finding (self-close never Stops), both positions are half right: the goal can only act at
intermediate Stops of a fired session, never at its terminal close.

---

## 4. Claims no report verified

| # | Claim | Status |
|---|---|---|
| U1 | The A06 and A09 **skeptic reports exist** | **Not on disk.** `ls` of the report dir: skeptic files for A01(2), A02, A03, A04, A05(2), A07(2), A08, A10(2), A11(2), A12(2); **none for A06 or A09**. Every A06/A09 skeptic number lives only in the lead's context (delivery-contract failure, research-subagents skill field 7). |
| U2 | A02's 36/85 hand-read TRUE verdicts | Recorded nowhere (A02-skeptic: `sample.txt` carries no marks). |
| U3 | A09/A11's "21 of 22 blocked commands are compound fixture scripts" | Neither skeptic re-read the 22; A09's own skeptic notes it. |
| U4 | A07: "the harness override leaves no trace" | Refuted (C3): 4–6 `type:"system"` records exist. |
| U5 | "Stop chain identical in all five config dirs" (A09 D08, lead §3) | A12-skeptic2 measured 100/94/95/94 hooks and 21/20/20/20 events across accounts (secondary/tertiary/quaternary lack `PostToolUseFailure`). The Stop list may match; "identical" was asserted for the whole. |
| U6 | Whether `SessionEnd`/`Stop` hooks run when `hf_close_pane` closes the pane (self-close) | Nobody measured. permission-archive `resolved_by: SessionEnd` = 16 shows SessionEnd fires sometimes; whether it fires on a `kitty @ close-window`/`it2 session close -f` is open — and it decides whether §0's gap can be closed at SessionEnd or only inside `self-close`. |
| U7 | A04 R6: "a goal dies with `--recycle`" | Refuted by source: `handoff-fire.sh:4676-4684` inherits the live condition into the successor (`CC_RECYCLE_GOAL_INHERIT` default 1). |
| U8 | Lead §3: 104 of 127 no-record closes ran on 2.1.220 | Not reproduced (C5): 2.1.220 sessions today 17 closes / 16 rows. |
| U9 | A01 §7: 469 = 469 exact identity | Not reproduced (C5): 649 vs 558 at 19:02Z. |
| U10 | A08 E7: whether N=10 or N=12 is the right subagent default | Both axis and skeptic say unmeasured; still unmeasured. |
| U11 | A10 R7: the two beat-less pids lack `jq` | Refuted (M6): jq is `/usr/bin/jq`; cause open. |
| U12 | A01-skeptic: `timeout` absent for "0/3 live processes ⇒ every knob dead" | Overstated (M6): 7/25 lack it, 18/25 have it. |
| U13 | A06 R6 / lead §5: Workflow available headless | Lead measured yes (`-p` tool list includes Workflow); still unmeasured for *subagents* (this session: absent). |
| U14 | A12-skeptic2: "a potential 13th Stop hook" from the plugin | Not live — plugin not in `enabledPlugins` (C10). |
| U15 | A05/A09: extrapolated permission-freeze cost | A09-skeptic opened the archive (chronic, 11–270 h/day); the daily curve is measured, the "wave-day artifact" caveat is withdrawn — carry the measured curve, not either extrapolation. |

---

## 5. Sources the question required that nobody opened

Census: `grep -l -F <name> *.md` over all 29 report files in the directory.

| Source (named in the wave brief unless marked) | Cited by | Why it mattered |
|---|---|---|
| `docs/research/stop-chain-wave2-2026-09-03/` (5 files) | **0** | `reader.md`: kill-switch reader blind to multi-line messages (fixed `bf6385171`); `guard.md`: **33 same-Stop double-fires** session-continue+completion-assert, 39 sids, over 1,335 evaluations 08-25→09-03 — A07's exact domain; `custody.md`, `agentreport.md`, `goal-idl-harvested.md`. |
| `docs/research/stop-hook-wedge-2026-08-17.md` | **0** | "Stop-hook chain wedges at 12/13 with no live child" — A01/A07 territory; also records that a whole config dir (`~/.claude-quaternary`) vanished once. |
| `docs/research/goal-condition-best-practice-2026-08-09.md` | **0** | The standing argument for `--goal` as default; A04 R3 argues the reverse without engaging it (C13). |
| `docs/research/goal-safe-2way-comms-2026-08-13.md` | **0** | The mailbox/wake architecture A04 R3 and A11 R2 lean on. |
| `docs/research/idle-recycle-not-proactive-2026-08-08.md` | **0** | Root cause of a disarmed `waiting-recycle` (removed `cc-roles/desk`) — A10's domain; A11-skeptic re-found the desk role file independently. |
| `docs/research/close-integrity-recensus-2026-08-20.md` | **0** | The efficacy re-census of the design A02 re-measured. |
| `scripts/conviction-census.py` | **0** | The shipped instrument for A02's question; A02 wrote `extract_idle.py` instead. |
| `~/.claude/autonomy/idl.jsonl.*.gz` (8 archives, from 08-29) | A07, A11 only | M5. |
| `.claude/settings.local.json` (shared checkout + 21 worktrees) | A12-skeptic2 (shared only) | M3 — the permission axis (A05) read neither. |
| `~/.claude/plugins/…/security-guidance/…/hooks.json`, `installed_plugins.json`, `enabledPlugins` | A12-skeptic2 (hook), nobody (enablement) | C10. |
| `scripts/lib/spawn-presence.sh::cc_sp_active` | A10-skeptic, A11 | A10 proposed re-implementing it. |
| `scripts/handoff-fire.sh` **self-close path** as a close surface | **nobody** | §0. |
| `tests/handoff-fire-capacity-gate.bats:84` (`CC_FIRE_ACTIVE_OVERRIDE=0` in setup) | A11-skeptic | why a 100 %-blind term has a green suite. |
| `~/.claude/autonomy/permission-archive/` | A05; A09 named it and did not open it | A09-skeptic did. |
| `docs/research/FRONTIER_HOLES.md` | 0 | not needed by any axis — fine. |

---

## 6. Critic recommendations (beyond C-R1, C-R2 above)

| # | What | Conv. | Effort | Evidence | Fail direction | Files |
|---|---|---|---|---|---|---|
| C-R3 | **Order the landing:** A11 R3 (un-blind the fire gate) → a `cc-backlog` fold cache → then any of A02 R4 / A06 R2-R3 / A11 R2 that mint rows. Strike A06's "capacity is not the constraint". | 90 | S (ordering) | C1, C2, C7 | Landing row-minters first errs toward more silent Stop-hook kills (A01: killed hooks write nothing) on a hotter box. | `scripts/handoff-fire.sh`, `bin/cc-backlog`, synthesis doc |
| C-R4 | **Re-file step 2's flip**: `migrations/NNNN-enable-todo-tools.sh` (`# migration-class: c10`, five config dirs per `0021-fleet-hook-parity.sh:98`) + `cc-backlog needs` row with `--run`. Pair with the CLAUDE.md clause (A03 R2/A08 E5) and a *lineage*-scoped open-tasks term (C8), not session-scoped. | 92 | S | C12, C8; env unset 5/5; no migration; no open row | Errs toward noise (four deferred tool names, +26 tokens); cannot silence anything. | `migrations/`, `CLAUDE.md`, `scripts/wrap-ledger.sh` |
| C-R5 | **Adopt the IDL abstain count as the kill-switch oracle** and ship only the brief discipline (A08 E2's sentence, no numbers). No regex change. | 85 | S | C4: 1 abstain / 530 Stops today | Errs toward leaving a rare disarm in place (0.19 %/Stop); the regex change errs toward D-8 (forcing a session told to report-and-stop to keep working) with nobody in the pane. | `CLAUDE.md`, `commands/handoff.md` |
| C-R6 | **Correct the brief premises in the synthesis**, not just in footnotes: IDL is 11 days (M5); `ENABLE_STOP_REVIEW` is the plugin's gate (C10); Workflow is headless-available and subagent-absent (M4); `timeout` is homebrew-only and `jq` is system (M6); the harness cap is (inferred) a no-progress bound (C3); `--recycle` inherits the goal (U7). | 95 | S | measured above | Errs toward more prose; the alternative is seven resident wrong facts. | synthesis doc, `CLAUDE.md:185,399,502,888` |
| C-R7 | **Build the session-termination census as a shipped instrument** (`scripts/measure-closes.py` sibling): per dead session, terminal class ∈ {Stop, self-close, recycle, drain-recycle, frozen, killed, api-error}, joined to beat liveness and the permission archive; run it in the IDL alarm so the Stop-chain denominators are stated beside every "% of Stops". | 88 | M | §0: 24 % / 56 % / ~20 % today | Errs toward another counted line nobody reads unless `/wrap` and the alarm consume it (memory: detector-with-no-owner). | `scripts/measure-closes.py` or new script, `scripts/idl-abstain-alarm.sh` |
| C-R8 | **Publish the two missing skeptic reports** (A06, A09) from the lead's JSON to disk before the synthesis cites them. | 97 | S | U1 | Errs toward nothing; without it the synthesis cites unverifiable numbers. | report dir |

---

## 7. What I did not do
- No 30-day re-derivation of the close census (A01's 11,871 / A02's 10,811) — the today-only
  measurement in C5 was enough to show both attributions fail to reproduce.
- No binary read for the `qd` reset semantics (C3) — flagged as the one read that settles it.
- No measurement of whether `SessionEnd` hooks fire on `hf_close_pane` (U6).
- Did not re-verify A11-skeptic's fixture correction (36 selftest fires) or A02-skeptic's noise census
  (490/2,045); both are stated with commands and I found nothing contradicting them.
- OASIS: the last two sources opened (`drain-recycle-fire.sh` header, `handoff-fire.sh:4636-4684`)
  confirmed rather than added; stopped there.
