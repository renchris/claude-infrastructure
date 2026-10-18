# Axis 05: the frozen-DoD mechanism and the backlog/dispatcher

This was a read-only investigation. The only repo file written is this report. Scratch files went
under `/tmp/axis05/`: `all.json` is the `cc-backlog list --all --json` fold, `raw14.jsonl` is the
last 14 days of backlog records, `idl14.jsonl` is the IDL window, and `filtered.md` is the simulated
DoD filter. I edited nothing and ran no hook in a mode that writes state. The commands I ran are
`dod-persist.sh path|get`, the `dod-path.sh` read functions, `cc-backlog list`, jq/grep and plutil.

Every number below is labelled. **[M]** means measured, followed by the command or its scratch file.
**[E]** means estimated, followed by the method.

---

## 0. Correction to the incident brief (conviction 92%)

INCIDENT.md says: "The `Scope (frozen): research only …` line written at intake was then used as the
reason the implementation was out of scope." **No such line was ever written.**

- [M] I ran `grep -o 'Scope (frozen)[^"]\{0,250\}'` over both halves of the transcript and a jq pass
  over the assistant text for `scope`. Before 20:03Z, the session's assistant text contains **no**
  `Scope (frozen)` or `Scope (grown)` line. The only `Scope (frozen)` strings in the file before the
  incident are quoted rule text and a brief for a different task (the load study).
- [M] `grep -n wt-cc-004752-67086 ~/.claude/autonomy/dod/repo-86523465733a9afe.md` finds exactly one
  capture for this toplevel. It is at line 381, written `2026-10-18T20:04:37Z (manual-set)`, and it
  holds the post-incident close-behavior scope. Nothing was ever captured for the startup-hooks study.
- The ask was a single verb: "ultracode research the best startup hook improvements …". It is the
  user record at 2026-10-18T06:04:35Z in
  `~/.claude-secondary/projects/-Users-chrisren-Development--worktrees-wt-cc-004752-67086/5759497b-3947-4fd7-9d8b-e095bf134dbf.jsonl`.
  "research only" first appears in the close line itself, at 14:27:47Z: "Follow-on: the
  implementation waves in README §5 haven't started, because this pass was research only." The agent
  later conceded at 20:03:29Z: "I used "this pass was research only" as cover".
- The research-program exemption did **not** apply. [M] The registry
  `~/.claude/autonomy/research/programs.json` lists one program, `truememory-2-0`, certified, with
  cwd root `.worktrees/tm2-plan`.

So the frozen-DoD mechanism did not justify the stop through its *text*. It justified it through
**an absent own contract plus a foreign contract that read as met** (section 1.3). The verb
"research", unrecorded, did the scoping.

The pattern is still real across sessions. [M] `cat ~/.claude/autonomy/dod/*.md | grep -o "Scope
(frozen):.*" | sort -u` gives 345 distinct frozen lines over 81 stores. Of these, 103 name a research,
investigate, audit, study or diagnose verb. At least 5 explicitly exclude implementation, for example:
- "Research only — no …" (RESO_COM_ACQUISITION_PREP).
- "Implementation of the plan is its own Phase 1+ and is not this session's deliverable"
  (screenshot pipeline, hammerspoon store `repo-3bbc3c28d00bc718.md:9`).
- "research + planning only, no implementation" (Reso onboarding).

---

## 1. Q1: once a scope says research-only, can implementation become in scope?

**Answer: by rule yes; mechanically no.** Nothing makes it happen automatically, and the
completeness rule pulls the other way. Conviction 90%.

### 1.1 What the rule says

- `CLAUDE.rules.slim.10-session-close.md:26`: "Freeze the DoD at intake … Close-time completeness is
  a diff against that line, not a fresh judgment." A research-only frozen line therefore makes "every
  research item delivered" the whole completeness test, and implementation drops out by
  construction.
- `:39` routes out-of-scope discoveries through the Follow-On Gate: "PASS → do it now and append
  `Scope (grown): +<item>`".
- `:67`, F1, covers "nothing left on the table". `:68`, F2, says: "Above 90% there is nothing to ask:
  implement."
- `:184` says "'Out of scope' … are reasons, not impossibilities: drive it … or drop it."
- `:99` (E0) says a read-only turn that names drivable work runs the gate on each item.

So the rule text already makes waves at 90% or more drivable. But it reaches them only if the agent
**classifies its own deliverable's recommendations as "out-of-scope discoveries"**. The research's
consequences are the deliverable, not a discovery, so the gate's trigger wording does not obviously
cover them. Line 26 ("not a fresh judgment") then actively discourages re-judging the scope at close.
Conviction 80% that this wording gap is a real contributor. Evidence: the agent's own reading at
20:03:29Z was "your rules already say 'out of scope' isn't a reason". The text was there, and it went
unapplied for 6 hours of turns.

### 1.2 What the machinery does with `Scope (grown)`

- `hooks/dod-persist.sh:88-96` and `:478-493` only **capture** distinct `Scope (grown)` lines from the
  transcript at PreCompact. `:339` and `:444` **re-inject** them at SessionStart as "already
  authorized, do NOT re-ask".
- [M] `grep -rln "Scope (grown)" hooks scripts bin commands skills` returns `hooks/dod-persist.sh`
  only. No ledger term, Stop hook or dispatcher reads a grown line. Growth is purely a convention
  that survives compaction.
- `scripts/wrap-ledger.sh:924-931`: `REMAINDER` counts only `- [ ]` checkbox lines in the DoD store.
  A one-line frozen or grown scope contributes 0. This is a structural cap: the ledger can **never**
  see an unfinished scope written as prose.
- The checkbox route is closed too. The store is append-only (`dod-persist.sh:98-128`, "never
  overwrite"), and no verb ticks a box. `hooks/session-continue.sh:997-999` explicitly refuses to fire
  on REMAINDER: "a remainder is the steady state … Firing on it would block every close in this
  worktree forever." [M] Running `grep -cE '^\s*[-*]\s+\[\s\]'` over all 81 stores finds 0 unchecked
  boxes, and the sum of `[x]` boxes is 38. Nobody uses the box channel today, and using it would be
  irreversible.
- [M] Usage: `grep -c "Scope (grown)"` over all stores gives **8** grown lines, against 345 distinct
  frozen lines. Exactly **one** is a research-to-implementation growth: `repo-3bbc3c28d00bc718.md:12`,
  "+fire the plan's implementation waves as dispatched sessions … (operator: 'Continue and drive',
  2026-09-13)". **The only recorded growth from research into implementation needed the operator to
  say "Continue and drive".** No agent has ever grown it unprompted. Conviction 85% that this
  generalises; it rests on 1 positive case and 0 unprompted ones.

### 1.3 New finding: the ledger computes SCOPE=met for this worktree from a foreign contract

Conviction 88%.

- `wrap-ledger.sh:912-918` reads `DOD_SCOPE` and `REMAINDER` through `dod_filter_for`. That is the
  **toplevel** filter, not the session-lineage filter that the SessionStart injection uses under
  `CC_DOD_LINEAGE_ONLY=1` (`dod-persist.sh:418`).
- `hooks/lib/dod-path.sh:157-176` keeps every block whose header has no `· toplevel=` stamp: "unattributable
  (pre-provenance) — inherited, never dropped".
- [M] I ran `bash /tmp/axis05/filt.sh`, which feeds `dod_filter_for` the store truncated to its
  pre-incident 380 lines with cwd set to this worktree. The result: **16** unattributable August
  blocks survive. The newest frozen line is "land prerequisite 1 of
  docs/research/dod-crosstalk-2026-08-18.md …", an unrelated August contract. The box count is 0.
- So `DOD=present`, `REMAINDER=0` and `SCOPE=met` (`:938-940`). The "completeness UNKNOWN" branch at
  `:2627-2631`, which is also what makes `operator-readout.sh` withhold "✅ SAFE TO CLOSE", is
  **unreachable for any worktree of this repo** [E]: the 16 legacy blocks pass every toplevel filter.
- Corroboration from the transcript: the 14:27:47Z close reads "✅ Complete and landed … the live
  layer is 1 commit behind, within its normal catch-up window". That is the `LIVE_SRC=behind` READOUT
  (`:2632+`), which is reachable only *after* the `DOD=absent` arm fails. The ledger therefore did
  certify scope as met on a contract that was not this session's.
- Effect on the incident: the rule at `:86`, "No findable scope is an unknown, not a ✅", could never
  trigger mechanically. The certificate told the agent its scope was met.

---

## 2. Q2: if the six waves had been filed with `cc-backlog add`, would `cc-dispatch` have driven them?

**Answer: it is a real path, but slow, and unreliable this week.** It is also not the path the rules
intend for drivable work. Ironically, the filing itself would have caught the incident. Conviction 80%.

### 2.1 What a filing would have done to the close

The filing, not the dispatch, is the part that mattered.

- `cc-backlog add` has 4 impossibility classes: needs-credential, needs-human, not-yet-true and
  no-capacity (`bin/cc-backlog:1145-1146`, refusal text at `:2428-2440`). A malformed
  `--why-not-now` is refused, and no-capacity is re-measured (`:2456-2460`). None of the 4 fits an
  agent-drivable wave, so the honest form would have been a **bare** add.
- A bare add is `FILED_MINE` (`wrap-ledger.sh:1378-1436`, jq at `:1418-1419`: open, filedBy is this
  session, no whyNotNow, no condition). It turns the ✅-eligible branch into **🔧 "backlog row(s) you
  filed this session are still open with no reason you could not drive them … drive each"**
  (`:2563-2566`), ranked above 🚀, 👤 and ✅.
- So six bare adds would have made "Good to close: yes" contradict the ledger. This is exactly the
  circularity the memory `a-plan-is-not-a-queue.md` records: "`FILED_MINE=0` is circular when you
  filed nothing … The omission returns as evidence of completeness."
- `CLAUDE.rules.slim.10-session-close.md:182-187` calls FILED "the exception" and says drive or fire
  (`handoff-fire.sh`) instead. The rules route drivable waves to **driving or firing**, not to the
  queue. That is the right design, because custody (`:21`) blocks ✅ until a fired peer returns, while
  a queued row frees the filer once a reason is attached.

### 2.2 Is the dispatcher running, and what does it claim?

- [M] `plutil -p ~/Library/LaunchAgents/com.claude.dispatcher.plist`: `cc-dispatch --once` every 300 s
  (`StartInterval 300`), with `CC_DISPATCH_PROJECT=claude-infrastructure` and `CC_FIRE_CLOUD=on`.
- [M] `launchctl list` shows `com.claude.dispatcher` loaded, pid 35337.
- The dispatch set comes from `scripts/dispatch-projects.conf`: claude-infrastructure, doc_classifier
  and reso-management-app are dispatchable, and the other projects are declared `skip`.
- The selection predicate is `status=="open"` (`bin/cc-dispatch:16-17`). **Blocked rows are never
  read.** Under V2 the per-pass decision covers the whole open backlog, with ceiling 12 and at most 2
  spawns per pass (`:44-60`, `:279`, `:440`).
- A dispatched worker's brief says: "Scope (frozen): drive this ONE item to finished-verified-landed"
  plus the row's DoD ref (`bin/cc-dispatch:3242-3244`). A wave filed with
  `--dod-ref docs/research/startup-hooks-2026-10-18/README.md` would therefore have produced a worker
  whose frozen scope is *implementation*. The path is real.

### 2.3 Measurements (14-day window from 2026-10-04T15:00Z unless stated)

| Quantity | Value | Source |
|---|---|---|
| Rows in store | 4,502: 6 open, 171 blocked, 4,325 done | [M] `jq '.[].status' all.json` |
| Non-done age | <1 d 16 · 1-3 d 20 · 3-7 d 11 · 7-14 d 25 · 14-30 d 45 · ≥30 d 60; median **17.7 d** | [M] `jq -f age.jq all.json` (age from `.ts`) |
| Blocked by class | needs-human 99 · unclassed 50 · not-yet-true 16 · needs-credential 6 | [M] same |
| Rows added in 14 d | 323: 250 done, 67 blocked (56 needs-human), 6 open | [M] `jq -f ttd.jq all.json` |
| Time to done, added in 14 d | p50 **1.1 h**, p90 **14.4 h** | [E] `lastTs − ts`, treating lastTs as the done time |
| Sources of those 250 | 212 `needs` (operator steps), 16 postland-verify; 92 of the 250 closed by falsifier | [M] `jq … .source / .closeKind` |
| Dispatcher claims | **423** claim events on **57** distinct rows; 47 of the 57 now done | [M] `raw14.jsonl` with `role=="dispatcher"` |
| Thrash | one row (`8f6752ec3f65`, "advance Instruction budget") claimed 265 and reopened 264 times | [M] per-id grep count |
| Done rows added in window that dispatch claimed | 45 of 250 (**18%**) | [M] `comm done14.txt dclaimed.txt` |
| Dispatcher fires | **26** in 2026-10-09T19:12Z..10-18T20:25Z (~9 d): next3 19, next2 4, next4 2, next 1 | [M] `idl14.jsonl`, `actor=="cc-dispatch" and action=="fired"` (IDL rotation limits the window to about 9 d) |
| Passes with "backlog empty" | 2,606 of 3,555 summaries (**73%**) | [M] same |
| Fires in the last ~22.5 h | **0**: 59 summaries since 2026-10-17T22:00Z, all `fired:0`; last fire 2026-10-17T21:57Z | [M] `jq 'select(.action=="summary")' idl.jsonl` |
| Current admission lock | held by a `--once` pass started 18:53:55Z, still running at 20:26Z (93 min); stderr says "wave-plan gave NO verdict (the account oracle did not answer)" | [M] `ps`, `dispatch.lock/owner`, `/tmp/claude-dispatcher.stderr.log` |
| Decision phase | about 1.3 min per item (20:22:15 → 20:23:37 → 20:24:52 for 3 items) | [M] IDL tail |
| Rows citing `docs/research/` (all time) | 135: 133 done, 2 blocked; 36 dispatcher-claimed; time to done p50 **6.6 d**, p90 **21.5 d** | [M] count; [E] time to done uses `lastTs − ts` |
| plan-open (cc-discover C2) rows | 482 done, 5 blocked; but 387 of the done are "C2-unscoped flood retr…" retractions and about 50 carry a sha; 58 dispatcher-claimed | [M] `jq … source=="plan-open"` |

### 2.4 Reading

Conviction 80%.

- **Not a graveyard for OPEN rows.** Open agent rows drain: 6 open in total, and the dispatcher idles
  on "backlog empty" in 73% of passes. Idle dispatch capacity existed while the six waves sat in
  prose.
- **A graveyard for BLOCKED rows.** 171 rows with a median age of 17.7 days are never read by the
  dispatcher.
- **Slow for research-shaped work.** Rows citing research docs take a p50 of 6.6 days to close [E].
  The fast p50 of 1.1 h belongs to operator steps and self-retracting repair rows, not to
  implementation waves.
- **Unreliable now.** It fired 0 times in 22.5 h, and one pass has held the admission lock for over
  90 min. "File it and the dispatcher will drive it" would not have been true on 2026-10-18.
- **The one automatic bridge from research to implementation is a plan file.** cc-discover's C2
  critic files "advance <plan>" rows from `find-plan.sh --list-open` (`bin/cc-discover:13`), and the
  `com.claude.discovery` launchd job runs it. A README §5 inside `docs/research/` is **invisible** to
  it. The one successful precedent, the screenshot study, wrote a `docs/plans/…_100P.md`. The
  startup-hooks study did not. Even so, the plan-open lane is noisy: 387 flood retractions, and one
  row thrashed 265 times.

---

## 3. Q3: proposals, each with conviction

All of these respect the constraints:
- silent when nothing drivable remains;
- never blocks a ⛔ (`cc-decide open --class C`) or a stated park;
- no net growth of the resident rule budget;
- no settings.json edits;
- no edit to `hooks/dod-persist.sh`, which another session owns.

### P1. A research ask freezes its consequence too

Rule change, net-zero budget. **Conviction 70%** that it is right; **45%** that it prevents
recurrence on its own (F2's "implement above 90%" was already resident and went unapplied).

Replace the second sentence of `CLAUDE.rules.slim.10-session-close.md:26` (and the same text in
`CLAUDE.global.md` § Session Close Protocol) with:

> Close-time completeness is a diff against that line, not a fresh judgment. A research or "should
> we …?" ask freezes its consequence too: each recommendation the research lands at >90% conviction
> is in scope (`Scope (grown): +drive <doc> §<n>`) the moment the doc lands. Only the operator's own
> words ("research only", "don't implement") exclude it, quoted in the frozen line.

- Cost: about 55 words.
- Matching cut: the research-program exemption is restated three times outside its own section.
  These are at `:99` (E0: "Inside an active research program, a completeness or pushback question is
  answered by relaying the certificate, and its named residuals are not drivable work (§ Follow-On
  Gate, Active research program exemption).", about 35 words), `:86` (about 25 words) and `:191`
  (about 30 words). Each can become "(research-program exemption: § Follow-On Gate)", which saves
  about 75 words net.
- It does not block a deliberate park: an operator-quoted exclusion still binds.
- It covers instances 2 and 3 of the incident ("should we investigate…?" followed by an ordered plan
  with step 1 above 90%).

### P2. Ledger term `RESEARCH_UNDRIVEN_MINE`: waves in a doc this session landed

Mechanical. **Conviction 75%.**

In `scripts/wrap-ledger.sh`, inside the ✅-eligible branch at the same rank as FILED_MINE (after
`:2563`):
- For each `docs/research/**/*.md` this session wrote (the same session-writes source that
  `session-continue.sh` uses), find sections whose heading matches
  `^#{2,3} .*(Implementation waves|Wave [0-9]+|Recommendations|Next steps)`.
- Count the waves that carry no disposition line. A disposition line is one of `Status: landed <sha>`,
  `fired <slug>` (with open or returned custody), `backlog <id>`, `decision <packet>`,
  `operator-only`, `parked: "<operator quote>"` or `dropped: <reason>`.
- A count above 0 gives 🔧 "N research wave(s) in <doc> have no disposition: drive, fire, or mark".

Properties:
- **Silent** for docs with no wave section, for docs this session did not write, and once every wave
  carries a disposition.
- Ranked below ⛔ (`:2505`), so a filed decision wins.
- A `parked: "<operator quote>"` line satisfies it, so a stated park is respected.
- On 2026-10-18 it would have fired on README §5's seven waves. Wave 6 is operator-only and would be
  satisfied by its marker; Waves 1-5 and 7 would have been counted.
- **Always-firing risk: low.** It is scoped to this session's own writes and needs a heading match.
  The main risk is heading false positives in non-research prose; restricting to `docs/research/` and
  `docs/plans/` mitigates that.

### P3. Make the frozen-scope reads use session lineage

Covers `wrap-ledger.sh` SCOPE and `DOD_SCOPE`. **Conviction 70%** on correctness; **40%** that it
alone would have changed this close.

- Read `SCOPE` from the same lineage filter that `dod-persist.sh` uses for injection, so a worktree
  inherits no foreign or unattributable contract as "met". The filter is `_dod_lineage_blocks`
  (`hooks/dod-persist.sh:168-192`), or a lib twin in `hooks/lib/dod-path.sh`, since dod-persist is
  owned elsewhere.
- With no own frozen line, `SCOPE=unknown`. The rung stays ✅ (operator ruling 2026-10-01) and
  `operator-readout.sh` withholds "✅ SAFE TO CLOSE".
- **Always-firing risk: medium.** Every session that never freezes a scope loses the certificate. It
  is not a block and not a continuation, but it changes the READOUT text on many closes. Pair it with
  P1 so research asks always freeze.
- Alternative, lower risk: stamp the 16 unattributable August blocks as legacy-closed. That needs an
  in-place store edit, which conflicts with INTEGRATE-only, so it is not recommended.

### P4. Route research waves through firing, not filing; keep the dispatcher as backstop only

Rule clarification inside P1's sentence, no extra budget. **Conviction 80%.**

- A drivable wave goes to: drive it here; fire it with `handoff-fire.sh --notify-back`, so custody
  blocks ✅ until it returns; or file a `cc-decide` packet if a value call remains.
- A bare `cc-backlog add` remains honest but keeps the filer at 🔧 (FILED_MINE). Do **not** add a
  fifth `--why-not-now` class such as `research-wave`. That would mint exactly the graveyard escape
  the class gate exists to prevent: rows citing research docs already wait a p50 of 6.6 d [E], and
  the dispatcher fired 0 in 22.5 h [M].

### P5. cc-discover critic C5 `research-waves`

Optional, operator-only activation. **Conviction 50%.**

- File one `advance <doc> §<wave>` row per undispositioned wave in a research README landed in the
  last 7 days, with the same disposition markers as P2.
- It gives the dispatcher's idle 73% of passes something to drain. It is the plan-open mechanism
  extended to research docs.
- **Always-firing risk: medium-high.** C2 shows the failure mode: 387 flood retractions, and one row
  claimed 265 times. It needs a date gate (new docs only) and P2's markers to stay silent.
- It only adds filed rows; the launchd job already exists. Rank it below P1, P2 and P4.

### P6. Unwedge the dispatcher

Operational, outside this axis's fix scope; reported only. **Conviction 60%** that it is wedged
rather than slow.

- Pid 35337 has held `dispatch.lock` for 93+ min, and no fire has happened since
  2026-10-17T21:57Z. The stderr says the account oracle did not answer.
- I touched nothing. It belongs to the owner of `bin/cc-dispatch` / `cc-wave-plan`.

---

## 4. Summary of convictions

| Claim | Conviction |
|---|---|
| No `Scope (frozen): research only` line was written; "research only" was the agent's unrecorded reading of the verb | 92% |
| Rule text allows research→implement growth (F2 above 90%, "out of scope is not an impossibility"), but no hook or ledger reads `Scope (grown)`, and `:26` "not a fresh judgment" pulls against it | 90% |
| REMAINDER can never see a prose scope; checkboxes are irreversible in an append-only store and refused by session-continue | 90% |
| The ledger certified SCOPE=met for this worktree from 16 unattributable August captures; completeness UNKNOWN is unreachable in this repo | 88% |
| Only 1 research→implement growth was ever recorded, and it was operator-prompted | 85% |
| Six bare adds would have turned the close into 🔧 FILED_MINE | 85% |
| The dispatcher drains open rows (73% of passes empty) but is slow for research-cited rows (p50 6.6 d [E]) and fired 0 in the last 22.5 h | 80% |
| A README §5 in docs/research is invisible to cc-discover; only docs/plans plans auto-file | 80% |

---

## Skeptic verdicts

This was a read-only skeptic pass on 2026-10-18. Scratch files are under `/tmp/skeptic05/`. **[M]** means
measured with the named command. **[E]** means estimated. Rung names follow the ledger: done (the
check-mark rung), loose-ends (the wrench rung), yours (the person rung) and blocked (the no-entry rung).

### Root causes

**RC1. No `Scope (frozen)` line was ever written.** CONFIRMED, 90%.
- [M] A jq pass over the assistant text in both halves finds no `Scope (frozen|grown)` line before
  20:03Z.
- [M] The only `dod-persist.sh set` call in either transcript runs at 20:04:35Z, on the INCIDENT commit.
- One thing the axis did not say: the study committed tracked files (`git add` at 13:18:07Z and
  14:18:54Z). That means rule `:26` ("the first time a task will write tracked files") required a
  freeze, and the agent skipped it. Nothing mechanical noticed (see RC4).

**RC2. Growth into implementation can only come from the agent, and the wording leaves a gap.**
WEAKENED, 70%.
- The mechanical half holds, and it is worse than the axis reported. The transcript extractors
  `extract_scope` and `extract_grown` run only in the `PreCompact` arm (`hooks/dod-persist.sh:463-493`).
  [M] `~/.claude/settings.json` has `"autoCompactEnabled": false`, and the last "Auto-compact
  triggered" line in `~/.claude/logs/sessions.log` is dated 2026-09-05. [M] Not one of the 351 block
  headers in the 78 stores carries a PreCompact label; all of them are `manual-set` or `goal-set`. So
  an inline `Scope (frozen)` or `Scope (grown)` line is never persisted. The "(`dod-persist.sh`
  captures it)" in `:26` is false in practice.
- The wording-gap half is contradicted by rule text that is already resident:
  - `:99` (E0): "A read-only turn that names drivable work … drive the passes".
  - `:189`: "every item at 90%+ conviction driven".
  - `:191`: "Offering researched, in-scope remaining work … is a defect".
- None of those needs the "out-of-scope discovery" trigger, and the agent itself conceded the rules
  covered the case (20:03:29Z). The defect is in applying the rule, not in its wording.

**RC3. REMAINDER sees only checkboxes, and the box channel is unusable.** CONFIRMED, 88%.
- `wrap-ledger.sh:924-931` counts boxes only. [M] The 78 stores hold 0 unchecked and 38 checked boxes.
- One correction: the box channel *is* read. `completion-assert.sh:1028` treats `REMAINDER>0` as a
  done-claim contradiction, and `wrap-ledger.sh:2514` puts it on the loose-ends rung. What stops it is
  that a box can never be ticked in an append-only store, not that nothing reads it.

**RC4. The ledger certified SCOPE=met from a foreign contract.** WEAKENED, 85% for the corrected
mechanism.
- The conclusion holds. The arm at `:2627` that reports "completeness UNKNOWN" is unreachable. [M] The
  transcript carries `READOUT=✅ Complete & landed — live layer converging (1 commit(s) behind…)`
  twice.
- The mechanism is wrong:
  - `DOD="present"` is set at `:905` for any existing file `dod_read_files` returns, *before* any
    filtering.
  - `SCOPE` (`:938-940`) reads only `DOD` and `REMAINDER`.
  - `DOD_SCOPE` feeds only `DRAIN_SCOPE` (`:935`; [M] grep finds no other consumer).
- With zero unattributed blocks the result would be the same. The 16 blocks do exist ([M]
  `bash /tmp/skeptic05/filt.sh`: 16 before the incident, 17 now), but they do not cause SCOPE=met.
  The repo-key store simply existing does.

**RC5. A bare filing would have caught the close.** CONFIRMED, 80%.
- Confirmed at `:1418-1419` and `:2563-2566`. `completion-assert.sh:1042` also consumes `FILED_MINE` as
  a contradiction, so six bare adds would have blocked the "yes" once.
- This is a missing safety net, not a cause. The rules call filing "the exception" (`:183`), and the
  agent believed nothing was open.

**RC6. The dispatcher path is real but slow and unreliable.** WEAKENED, 65%.
- These parts are confirmed:
  - The plist has `StartInterval 300`, and `cc-dispatch:16-17` selects only open rows.
  - [M] 2,601 distinct `passed: backlog empty` records, each paired with one of 3,555 summaries (73%).
  - [M] The last fire was 2026-10-17T21:57:43Z.
  - [M] pid 35337 still holds the lock: `ps` etime 01:53:55 at 20:47:49Z.
- These parts need correcting:
  - [M] `idl14.jsonl` has **130** distinct summaries since 2026-10-17T22:00Z, not 59. The 59 is the
    count in the rotated live `idl.jsonl`, which starts at 2026-10-18T12:16:17Z. All of them show
    `fired:0` either way.
  - [M] The research-cited rows behind "p50 6.6 d" were filed in 2026-07 (32), 2026-08 (86) and
    2026-09 (17), with **0 in October**. [E] The 3 such rows done since 09-18 have a p50 of 0.3 h. The
    6.6 d figure describes the summer queue, not today's dispatcher.

### Fixes

**P1 (rule: a research ask freezes its consequence).** WEAKENED, 45%.
1. The matching cut conflicts with the test suite. `tests/research-program-exemption-rules.bats:32-37`
   pins "relaying the certificate" in `:86` and `:99`, and "is not an offer" in `:191`. That is
   deliberate ("a pointer must live WITH its rule", REPORT §8 item 3). The cut requires changing the
   test and the ruling behind it.
2. The word arithmetic is off. [M] `wc -w` puts the three sentences at 25 + 31 + 33 = 89 words. The new
   text is 60 words, 48 of them new once the kept sentence is excluded. With the pointers, the net
   saving is about 26 words, not 35 (the summary) or 75 (§P1).
3. The prescribed inline `Scope (grown)` line is never persisted (see RC2). It has to be written with
   `dod-persist.sh set`.
4. It has no carve-out for an active research program, and it strips the exemption pointers at those
   three places.
5. It repeats F2, `:189` and `:191`, which were already resident and went unapplied.

Not always-firing, and it respects a quoted park.

**P2 (ledger term `RESEARCH_UNDRIVEN_MINE`).** WEAKENED, 55%.
- It can be built at `:2563`. The ledger has the transcript (`:227`, `:981`), and `session_writes_paths`
  reads subagent transcripts (`session-writes.sh:197-238`). [M] This session's subagents wrote
  `README.md` 31 times.
- (a) As written it cannot block the close. completion-assert has no general loose-ends contradiction:
  its terms are listed one by one (`:1028`, `:1042`), and arm D6 runs only when the rung is done or
  yours. A new term therefore changes only the READOUT. A "Good to close: yes" would be blocked only
  if `hooks/completion-assert.sh` also gains a `RESEARCH_UNDRIVEN_MINE` term, and that file is missing
  from P2's file list.
- (b) `dropped: <reason>` takes free text, so "dropped: research only" silences the term. The
  incident's own words would pass.
- (c) "Files this session wrote" over-attributes. [M] `grep -lErs` finds 49 files with 66 matching
  headings under docs/research and docs/plans, and none uses the marker vocabulary, so a typo fix
  makes the session own every old wave. Gate on headings this session's commits added.
- (d) [M] The regex matches 18 headings in the incident's directory. 10 of them are superseded axis or
  gap "Recommendations" sections, so the term would make the agent stamp markers on drafts.
- (e) It must stay silent inside an active research program (`:74-80`).
- The blocked rung (`:2505`) outranks it.

**P3 (read SCOPE through the lineage filter).** REFUTED as specified, 20%.
- Swapping the filter never reaches `SCOPE`, which derives from `DOD` (file existence, `:905`) and
  `REMAINDER`.
- Making it report unknown means redefining `DOD`. That conflicts with three tests:
  - `tests/wrap-ledger-research.bats:103`: a boxes-only DoD gives `SCOPE=met`.
  - `tests/dod-path.bats:80`: "DOD=present if either exists".
  - `tests/dod-path.bats:178-186`: the pinned fail-open inheritance.
- Its lever is weak. [M] "SAFE TO CLOSE" appears in the incident transcript only inside rule text, and
  0 IDL records in the 14-day scratch or the live file have reason `close-certificate` or `cert-*`.
- A different fix might work: key the READOUT arm on "this session wrote tracked files and has no
  frozen line of its own".

**P4 (fire, don't file).** WEAKENED, 60%.
- The core is sound: no fifth class, and `cc-backlog:2428-2445` already refuses one.
- It adds little:
  - `:184` already says "drive it (here, or by firing a session with handoff-fire.sh)".
  - `--notify-back` is already the default for every fire that is not a recycle (`handoff-fire.sh:248`).
- Its 6.6 d rationale is stale (see RC6).
- Firing can be refused too. At 20:05:35Z the post-incident fire was refused: "12 sessions are mid-turn
  against a ceiling of 8". It succeeded on retry, so the rule needs a retry-once clause.
- It inherits P1's budget problem.

**P5 (cc-discover critic C5).** WEAKENED, 30%.
- It depends on a dispatcher that has made 0 fires since 21:57Z and has a lock held for about 114 min.
- It depends on P2's markers, which no doc carries yet.
- The C2 critic is the precedent: [M] 387 of its 482 done rows are flood retractions.
- The report and the summary disagree. §P5 says "operator-only activation"; the summary says
  `operator_only:false`. The existing `com.claude.discovery` job would run a new critic with no
  operator action.

### Measurements

Each was re-run unless marked otherwise.

| Measurement | Verdict | Notes |
|---|---|---|
| 345 distinct frozen lines, 103 research verbs, ≥5 exclusions | Confirmed | ≥5 confirmed; 10 by a broader pattern |
| "81 stores" | Corrected | [M] `ls ~/.claude/autonomy/dod/*.md` gives 78 stores |
| 8 grown lines | Weakened | 7 distinct. One is a mention inside a frozen line (`repo-86523465733a9afe.md:117`), not a growth. The census counts only `set` calls (see RC2), so the near-zero growth rate is a capture artefact as much as a behaviour |
| Box counts, the 16-block filter result | Confirmed | |
| Backlog folds: 4502 rows, ages, classes, 14-day 323/250/67/6, p50 1.1 h / p90 14.4 h | Confirmed | p50 and p90 are [E] via `lastTs` |
| 212 needs / 92 falsifier, 45 of 250, 423 claims on 57 rows, 265-claim thrash | Confirmed | |
| 26 fires, 73% empty passes | Confirmed | |
| 59 summaries | Corrected | 130 (see RC6) |
| Lock time | Updated | Now about 114 min |
| 1.3 min per item | Confirmed | 20:22:15 / 20:23:37 / 20:24:52 |
| 135 research-cited rows | Confirmed | |
| Research-cited p50 6.6 d | Weakened | The sample predates October (see RC6) |
| plan-open 482 / 5 / 387 | Confirmed | |
| launchd jobs loaded, `is-active` exits 1 | Confirmed | |

### What the axis missed

1. **The inline DoD capture path is dead.** `autoCompactEnabled=false`, and 0 of 351 blocks came from
   PreCompact. No session's inline `Scope (frozen)` or `Scope (grown)` line has ever been stored or
   re-injected. Conviction 85%.
2. **SCOPE=met comes from the store file existing** (`:905`), not from the 16 blocks. Every repo with a
   repo-key store reads "met" after any clean close. Conviction 90%.
3. **completion-assert lists its contradiction terms one by one, and D6 runs only on the done and
   yours rungs.** Any new ledger term needs a twin there to block a "yes". Conviction 85%.
4. **Rule `:34` may have licensed the stop.** It is the only end-state row that names "research", and it
   is paired with "no auto-continue" ("Read-only / advisory / research (no tracked writes)"). That is
   a plausible lexical source for "this pass was research only"; the parenthetical excluded this
   session, which committed docs. Conviction 50%.
5. **Every fix here needs a research-program carve-out, and the existing suite pins the exemption at
   each rule** (`tests/research-program-exemption-rules.bats`). Conviction 85%.
6. **Firing has a capacity-refusal mode** (the 20:05:35Z refusal). "Fire it" needs "retry once" to be a
   complete disposition. Conviction 70%.
