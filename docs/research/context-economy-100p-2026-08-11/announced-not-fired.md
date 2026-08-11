---
status: closed
created: 2026-08-11
owner: desk
---

# The announced-but-never-fired failure — is it still live

*Axis `announced-not-fired` of the context-economy 100th-percentile assessment `wf_5e9f820e-438`. Verdict: [`../context-economy-100p-2026-08-11.md`](../context-economy-100p-2026-08-11.md).*

**At 100th percentile:** `NO`

**Verdict.** Still live and confirmed recurring (a genuine death 2026-08-10T12:39Z holding an unfired brief), but the fleet cannot MEASURE its own rate: a successful `--recycle` and a death produce byte-identical transcript tails, and the only discriminator — `handoffs.jsonl` — records success only (8 `recycle-engaged`, 0 `recycle-dead`, 0 `recycle-unverified` in 1,167 rows).

**Load-bearing claim.** The failure is not "the model forgets to fire" — it is that firing requires a mandatory hand-authored payload (`--prompt-file` is REQUIRED, `scripts/handoff-fire.sh:5701`, non-empty enforced at `:5706-5707`), so the escape from a full window costs a MEASURED median 20,864 tokens (a `/handoff` invocation, n=55) plus 2-4 turns, and there is NO brief-free recycle any model can fire in one call at 85% fill. The one zero-model actuator that composes its own payload (`hooks/waiting-recycle.sh:1102-1129`) is armed LIVE for exactly ONE cwd and fired 0 times in the last 5 hours against 5,380 evaluations.

**Shortest fix.** Add a brief-free mode to the sanctioned rail — `handoff-fire.sh --recycle --carry-dod` (no `--prompt-file`) that composes the payload from disk exactly as `hooks/waiting-recycle.sh:1102-1129` already does (standing brief template + frozen DoD from `hooks/dod-persist.sh` + a re-derive-from-disk directive). That converts the escape from ~21K tokens and 3+ turns into ONE Bash call at any fill, and it reuses code that already exists and is already tested. Pair it with a one-line addition to `emit_recycle_event`'s callers: emit an `intent` row at handoff-fire ENTRY (before the `__recycle` re-exec), so a session that dies between deciding and actuating leaves a row instead of nothing — today that whole class is invisible to every sensor.

**Skeptic: REFUTED** (confidence high)

> Every load-bearing element of the claim fails on primary sources. (1) The mandatory `--prompt-file` is real but does NOT mandate a hand-authored brief — only a non-empty file; an 83-byte payload passes every gate and reaches launch, so a brief-free one-call recycle DOES exist and costs ~20 tokens, not 20,864. (2) The 20,864-token figure measures the `/handoff` SKILL, which the operator's own disposition table assigns to the Handoff row; the Recycle row's prescribed command is `handoff-fire.sh --recycle`. It measures the wrong disposition, and at the 1M windows actually recorded it is 2.1% of the window — it cannot be the mechanism of a death at 85% fill. (3) The claim contradicts itself: its own anchor is a session that died HOLDING a written brief, i.e. after the payload cost was already paid. (4) That anchor does not exist: `cc-ctx-audit --summary --since 7d` reports 0 wall hits in 0 sessions, and an independent exact-normalised-equality scan across all FOUR config dirs finds zero — the "2026-08-10T12:39Z death" is a loose-substring false positive, and this fleet's own CLAUDE.md contains the string "Prompt is too long", so it is loaded into every transcript. (5) "Armed LIVE for exactly ONE cwd" is a one-config-dir sampling defect: `live-*` sentinels number 11 across four dirs (1 + 1 + 9). (6) "Fired 0 times against 5,380 evaluations" is a count over a requeuing subject with an empty qualifying population — 68 distinct sids, only 3 ever reached a fill reading, max fill 24 vs floor 25. (7) "Records success only" is false twice: `recycle-dead`/`recycle-unverified` are emitted on failure with an out-of-band alarm, and a SECOND store the claim never opened — `~/.claude/autonomy/recycle-events.jsonl`, 2,545 rows — carries 5 `executed` verdicts (3 against real sessions), so the zero-model actuator has fired live. (8) The claim's "byte-identical ledgers" sentence is the repo's own PRE-FIX comment, lifted and re-presented as current state; the fix landed 2026-08-09 and 8 real `recycle-engaged` rows now exist, the latest 2026-08-11T04:25Z. What survives is a DIFFERENT gap, already in the brief's ground truth: 5,503 of 5,526 transcripts have no recoverable window denominator (99.6%), so fill p95 rests on n=23.

Evidence: METHOD — every figure below is MEASURED by me this session from the named instrument; nothing is quoted from the other investigator or from a doc's claim about itself.

A. THE "BRIEF-FREE RECYCLE DOES NOT EXIST" CLAIM — REFUTED BY EXECUTION.
`scripts/handoff-fire.sh:5701` (`[ -n "$PROMPT_FILE" ] || … --prompt-file is required`) and `:5706-5707` (`[ -s "$PROMPT_FILE" ] || … empty payload fires a task-less successor (FM-D)`) are exactly as cited — but they gate a NON-EMPTY FILE, not authored content. Positive control (MEASURED): I wrote an 83-byte payload and dry-ran the real script —
  `printf 'Continue: re-derive state from disk (git status, plan doc, cc-board), then resume.\n' > /tmp/minrecycle.txt`  (83 bytes, ~20 tokens)
  `CC_FIRE_DRY=1 bash scripts/handoff-fire.sh --recycle --dry-run --prompt-file /tmp/minrecycle.txt --session-id …`
It cleared payload-empty, check_goal_length, check_slash_head, payload_pane_id_gate and payload_lint_gate, and printed the launch line: `command: cd /tmp && nocorrect CLAUDE_ISOLATION_SKIP=1 claude "$(cat /tmp/minrecycle.txt)"`. The whole escape is ONE Bash tool call (`printf … > f && handoff-fire.sh --recycle --prompt-file f`), ~60-80 tokens of tool input. "No brief-free recycle any model can fire in one call" is false.

B. THE 20,864-TOKEN FIGURE MEASURES THE WRONG DISPOSITION (INFERRED from policy + MEASURED windows).
Global CLAUDE.md § "Context is a CLOSE-TIME decision" splits the two rows explicitly: ♻️ Recycle → `handoff-fire.sh --recycle`; 📤 Handoff → `Skill(handoff)`. A median over `/handoff` invocations (n=55) therefore prices the Handoff row and is silent on the Recycle row, which is the one that escapes a full window in place. Scale check: the only `executed` rows carrying a denominator record `window:1000000` (recycle-events.jsonl, 2026-07-31/2026-08-01), so 20,864 tokens = 2.1% of the window — a cost that cannot explain a death at 85% fill. I could not re-derive their arithmetic; I refute its relevance, not its value.

C. THE ANCHORING INCIDENT DOES NOT EXIST (MEASURED, two independent instruments).
  1. `cc-ctx-audit --summary --since 7d` (the repo's sanctioned outcome reader) → `wall hits (hard context refusal) since=7d : 0 event(s) in 0 session(s)` · `compactions … 0 event(s)`. The 7d window covers 2026-08-04 → 2026-08-11 and therefore 2026-08-10T12:39Z.
  2. My own scan, not trusting that tool's roots: exact normalised equality (`(text|ascii_downcase|trim) == "prompt is too long"`, assistant messages only) over every `*.jsonl` touched since 2026-08-09 in `~/.claude/projects`, `~/.claude-secondary/projects`, `~/.claude-tertiary/projects`, `~/.claude-quaternary/projects` → ZERO rows.
  THE TRAP THEY FELL INTO IS DOCUMENTED IN THIS REPO: `bin/cc-ctx-audit:151-154` — "A wall hit is an assistant message whose ENTIRE normalised text equals the API's refusal string. NEVER a substring: a loose grep matched 18 transcripts where only 7 sessions had actually hit it — the difference being prose ABOUT the error." I reproduced it: a naive `rg 'Prompt is too long'` returns 20+ files per config dir, and inspecting one (`~/.claude-next/projects/…/b00a9029….jsonl`) shows the match is CLAUDE.md's own § Context Stewardship text ("…What actually kills sessions is a bare `Prompt is too long` API refusal: **7 sessions, 10 events…**"), which is loaded into EVERY transcript in this fleet.

D. "ARMED LIVE FOR EXACTLY ONE cwd" — ONE-CONFIG-DIR SAMPLING DEFECT (MEASURED).
`hooks/waiting-recycle.sh:202` — `STATE_DIR="${CC_WR_STATE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/waiting-recycle}"` — the arm store exists once PER CONFIG DIR. Enumerating `live-*` sentinels: `~/.claude` 1 (`live-df1308af96473054`) · `~/.claude-next` same file · `~/.claude-tertiary` 1 (`live-e181330604ffe33f`) · `~/.claude-quaternary` **9**. Total 11 distinct live arms across 4 dirs. Reading only `~/.claude` sees 1 of 11.

E. "FIRED 0 TIMES AGAINST 5,380 EVALUATIONS" — A COUNT OVER A REQUEUING SUBJECT WITH AN EMPTY POPULATION (MEASURED, `~/.claude/autonomy/idl.jsonl`, fleet-shared: `IDL` is hardcoded to `$HOME/.claude/autonomy/idl.jsonl` at waiting-recycle.sh:201, so it is NOT per-account).
  Window in the live file: 2026-08-11T01:28:16Z → 06:32:38Z (5h04m). waiting-recycle rows: 5,143.
  Dispositions: `abstained not-armed` 3,295 · `abstained disarmed` 1,452 · `abstained dirty-tree-hold` 272 · `abstained recycle-machinery` 16 · ~106 `below-threshold-no-tell` · `fired busy-nudge` 2.
  Distinct sids evaluated: **68**. Distinct sids that reached a fill reading at all: **3**. Distinct sids `not-armed`: 39.
  Every fill reading in the window is `used=0..24` against `floor=25`. ZERO evaluations reached even the advisory floor, let alone the Stage-2 fire threshold. An actuator that fires 0 times when 0 of its population qualifies is healthy — this is the fleet's own `cap-whose-population-is-empty` / `alarm-polarity` pattern. (Cross-check: `stage2-live`/`stage2-shadow` appear 0 times in the live IDL AND in all 8 gzipped archives back to 2026-08-08 — consistent with "nothing qualified", not with "the actuator is broken".)

F. "THE ONLY DISCRIMINATOR RECORDS SUCCESS ONLY" — FALSE TWICE.
  1. Failure classes are wired and LOUD: `scripts/handoff-fire.sh:4307` emits `recycle-unverified`, `:4340` emits `recycle-dead`, and `:4342` additionally raises `hf_alarm recycle-dead … "HANDOFF-RECYCLE-DEAD: pane $RSID relaunched but never engaged"`. `emit_recycle_event` (:657-676) encodes `engaged` as a deliberate TRI-STATE (true / false / absent). 0 dead rows means 0 dead recycles, not an unrecorded failure mode.
  2. A SECOND, INDEPENDENT STORE THE CLAIM NEVER OPENED: `~/.claude/autonomy/recycle-events.jsonl`, written by `ce_record_recycle` (`hooks/lib/context-econ.sh:141`) — 2,545 rows spanning 2026-07-30T02:44Z → 2026-08-11T05:43Z. Verdict distribution (MEASURED): `advised` 2,491 (fill 1,075 / size 705 / forecast 656 / threshold 55 / behavioral 12 / …) · `nudged` 23 · `shadow-would-fire` 12 · **`executed` 5**. Three of the five are real sessions with UUID sids and recorded denominators: `89922bd6…` 2026-07-31T17:56:46Z used=32% input=319,142 window=1,000,000 · `1ed02e2e…` 2026-08-01T08:26:20Z used=52% input=515,553 window=1,000,000 · `0226c221…` 2026-08-01T08:32:51Z used=37% input=371,642 window=1,000,000. The zero-model actuator HAS executed against live sessions.

G. THE CLAIM'S OWN KEY SENTENCE IS THE REPO'S PRE-FIX COMMENT, RE-PRESENTED AS CURRENT STATE.
`scripts/handoff-fire.sh:621-626` reads verbatim: "A RECYCLE THAT WORKED. Until now this was the one fire outcome on the box that wrote NOTHING … so a successful recycle and a recycle that never happened produce byte-identical ledgers. Measured 2026-08-09: 1012 rows spanning 41h carry ZERO recycle rows of any class … That is the same non-emission this change exists to abolish." The fix landed. `~/.claude/logs/handoffs.jsonl` (1,167 rows, confirming their count) now carries **8 `recycle-engaged`** rows, ALL `under_test:false`, 2026-08-09T08:19Z → **2026-08-11T04:25:14Z**, each with `prev_sid` and a measured engagement latency ("a real assistant turn within 0-15s"). Their own "8 recycle-engaged" number is the evidence the gap they describe was closed two days before they described it.

H. WHAT ACTUALLY SURVIVES (MEASURED — and it is the brief's ground-truth gap, not theirs).
  `cc-ctx-audit --summary --since 7d`: `p95 fill = 61.8% (p50=38.5%) over n=23` with `EXCLUDED for no recoverable denominator: 5503 of 5526 transcripts` (99.58%). The fleet cannot measure its own fill on 99.6% of sessions.
  Adjacent, and new: `bin/cc-ctx-audit:58-60` `DEFAULT_ROOTS` names `~/.claude/projects`, `~/.claude-tertiary/projects`, `~/.claude-quaternary/projects` — it OMITS `~/.claude-secondary/projects`, one of the four accounts, in the very tool whose own header warns that "reading only ~/.claude would silently miss two thirds of the denominators". Immaterial to this verdict (my 4-dir scan also found 0 wall hits), but it is a real blind spot in the sanctioned instrument.
  And the coverage fact behind (E): waiting-recycle's deterministic arm reads fill for 3 of 68 sessions it evaluates. That is a genuine 100th-percentile shortfall — it is a POPULATION gap, not a payload-cost gap.

**Instrument defect:** Five distinct instrument defects, in descending severity. (1) LOOSE-SUBSTRING DETECTOR ON A CORPUS THAT CONTAINS ITS OWN SEARCH STRING — the "genuine death 2026-08-10T12:39Z" is a match on CLAUDE.md's § Context Stewardship prose about the refusal, which is injected into every transcript in this fleet; the repo already documents this exact false positive at bin/cc-ctx-audit:151-154 (loose grep 18 vs true 7), and the exact-equality detector returns 0 events over the same period across all four config dirs. (2) ONE CONFIG DIR TREATED AS THE FLEET — waiting-recycle's STATE_DIR is per-CLAUDE_CONFIG_DIR (waiting-recycle.sh:202), so "armed LIVE for exactly ONE cwd" is 1 of 11 live sentinels. (3) COUNT OVER A REQUEUING SUBJECT WITH AN EMPTY QUALIFYING POPULATION — 5,143 evaluations are 68 sessions polled repeatedly; only 3 ever reached a fill reading and the maximum fill was 24 against a floor of 25, so "0 fires" is the healthy reading, not evidence of inertness. (4) A POPULATION THAT EXCLUDES THE ANSWER — the recycle-outcome enum was checked in handoffs.jsonl only, missing ~/.claude/autonomy/recycle-events.jsonl (2,545 rows, 5 `executed`), which is the store that answers "did the zero-model actuator ever fire". (5) A DOC'S PRE-FIX COMMENT READ AS CURRENT STATE — the "byte-identical ledgers" finding is quoted from handoff-fire.sh:621-626, which is the changelog OF THE FIX, not a description of today; the 8 recycle-engaged rows the claim itself cites are that fix working.

---

## Findings

### `[MEASURED][GAP]` The failure mode recurred and is confirmed live: session e5d3628d died 2026-08-10T12:39:10Z with its last real record being the tool_result of a Write to /tmp/fire-lead-recycle.txt, at 770,657 input tokens occupancy, and the fire log shows ZERO rows of any class in 12:35-13:05Z despite covering that window.

- **Evidence:** Transcript /Users/chrisren/.claude/projects/-Users-chrisren-Development-claude-infrastructure/e5d3628d-8aac-428a-b2ea-bfaa7cc023b7.jsonl records 2312-2328; cross-join against ~/.claude/logs/handoffs.jsonl (1,167 rows, span 2026-08-08T20:58:51Z -> 2026-08-11T05:42:24Z) returns no row with prev_sid e5d3628d and no row at all in the 30-minute bracket.
- **Source:** `~/.claude/projects/.../e5d3628d-*.jsonl ; ~/.claude/logs/handoffs.jsonl`

### `[MEASURED][GAP]` CORRECTION to the memory file's implied recurrence rate: the transcript signature it teaches (transcript ends at a brief's tool_result, no further assistant turn) has a ~50% false-positive rate. Of the 4 such cases inside the fire-log window, 2 were SUCCESSFUL recycles.

- **Evidence:** ff519bfd (brief 2026-08-11T01:18Z) -> `recycle-engaged engaged=true pane=113 detail="recycled in place; a real assistant turn within 10s"` at 01:19:30Z. 8f478e5c (brief 04:24:25Z) -> same row at 04:25:14Z, plus a `goal-arm` row `pane 113; condition 589 chars` at the same second. Both transcripts end at the Write tool_result with no handoff-fire tool_use recorded — i.e. a successful --recycle DROPS the firing turn's record (the /exit interrupt kills the process before flush). 3b0cd9ca is a third such case (recycle-engaged 2026-08-09T08:19:55Z pane=898).
- **Source:** `~/.claude/logs/handoffs.jsonl vs ~/.claude-quaternary/projects/.../{ff519bfd,8f478e5c}*.jsonl`

### `[MEASURED][GAP]` The recycle sensor is SUCCESS-ONLY in practice, so the announced-vs-fired rate is structurally uncomputable. 8 `recycle-engaged` rows exist; `recycle-dead` and `recycle-unverified` have ZERO rows.

- **Evidence:** jq class census over ~/.claude/logs/handoffs.jsonl: admitted 815, self-retire-peer 162, refused 152, goal-arm 27, recycle-engaged 8, trim 3. Root cause is architectural: emit_recycle_event runs inside the detached `__recycle` re-exec (handoff-fire.sh:650-668), so a session that dies BEFORE invoking handoff-fire produces no row of any class — the exact failure this axis is about is the one case the instrument cannot see.
- **Source:** `~/.claude/logs/handoffs.jsonl ; scripts/handoff-fire.sh:622-668`

### `[MEASURED][GAP]` Preparing a recycle costs a MEASURED median 20,864 tokens (p90 24,910, max 27,469) for the /handoff slash invocation alone, n=55 invocations across 3,222 transcripts.

- **Evidence:** Per-invocation delta between the last assistant input-token occupancy before the <command-name>/handoff record and the first after it. On a 1,000,000 window that is 2.1% — benign. On a 200,000 window it is 10.4%, i.e. at 85% fill a single /handoff consumes ~70% of remaining headroom. The trap the operator suspected is REAL but window-dependent. Note e5d3628d had already spent 27,045 tokens on a /handoff at 484,169 occupancy and still died at 770,657 on its second attempt.
- **Source:** `scan of ~/.claude*/projects/**/*.jsonl (n=3,222 files, 4 config dirs)`

### `[MEASURED][GAP]` There is NO cheap one-call recycle path available to the model. `--prompt-file` is a hard requirement of every fire including --recycle, and an empty payload is a named refusal class.

- **Evidence:** scripts/handoff-fire.sh:5701 `[ -n "$PROMPT_FILE" ] || { echo "!! --prompt-file is required" ...; usage 1; }` and :5706-5707 `[ -s "$PROMPT_FILE" ] || { ... emit_fire_refusal payload-empty ...; exit 1; }` ("an empty payload fires a task-less successor (FM-D)"). --recycle composes with --worktree/--cwd (:150-160) but never removes the payload requirement.
- **Source:** `scripts/handoff-fire.sh:5701,5706-5707,132-160`

### `[MEASURED][GAP]` The one mechanism that CAN fire a recycle with no model turn exists and is correct, but is gated off for the whole fleet: it is armed LIVE for exactly ONE cwd and produced 0 fires in 5,380 evaluations over the last ~5 hours.

- **Evidence:** hooks/waiting-recycle.sh:1102-1129 composes a payload and execs `"$HANDOFF_FIRE" --recycle --prompt-file "$pf"`. State dir ~/.claude/state/waiting-recycle holds exactly one `arm-` + one `live-` + one `brief-` sentinel (cwd /Users/chrisren/Development/claude-infrastructure, armed 2026-07-26T07:40:19Z), one `disarm-` (2026-07-31), and 3 `fired-` sentinels, newest 2026-07-31T10:56. IDL census 2026-08-11T01:28:16Z -> 06:23:02Z: abstained/not-armed 3,204 · abstained/disarmed 1,261 · abstained/dirty-tree-hold 272 · abstained/recycle-machinery 16 · rest below-threshold. Zero fires, zero advisories. 83% of abstentions are the ARM gate, not the threshold.
- **Source:** `hooks/waiting-recycle.sh:1102-1129 ; ~/.claude/state/waiting-recycle/ ; ~/.claude/autonomy/idl.jsonl`

### `[MEASURED][GAP]` boundary-handoff.sh cannot close the gap either — it is advisory-only by construction, and it abstained on every evaluation in the same 5-hour window.

- **Evidence:** hooks/boundary-handoff.sh:376-377 records `ce_record_recycle "$tel" advised`, :405 emits `{decision:"block",reason:$r,systemMessage:$r}` — it hands the work back to the model, which must then pay the ~21K-token /handoff. IDL dispositions for hook=boundary-handoff in the window are entirely `abstained/below-threshold:NN<73`, `abstained/no-telemetry`, `abstained/gate-not-green-at-head`, `abstained/team-assignee`.
- **Source:** `hooks/boundary-handoff.sh:376-377,405 ; ~/.claude/autonomy/idl.jsonl`

### `[MEASURED][STRENGTH]` The running bytes match HEAD — this is NOT a stale-deployed-bytes case. All four mechanisms are per-file symlinks into the checkout and trunk..HEAD = 0.

- **Evidence:** ~/.claude/hooks/waiting-recycle.sh, ~/.claude/hooks/boundary-handoff.sh, ~/.claude/scripts/handoff-fire.sh, ~/.claude/commands/handoff.md all resolve to /Users/chrisren/Development/claude-infrastructure/...; `git rev-list --count origin/main..HEAD` = 0. Both hooks are registered in ~/.claude/settings.json (lines 561, 826).
- **Source:** `readlink on ~/.claude/{hooks,scripts,commands}/* ; git rev-list ; ~/.claude/settings.json:561,826`

### `[MEASURED][GAP]` Announced-vs-fired headline over the full corpus: 150 sessions wrote a /tmp successor brief; 112 (75%) followed with a handoff-fire tool call in-transcript; 38 (25%) did not. 14 of the 38 end with the brief's tool_result as the last real record — but per finding 2 that 14 is an upper bound contaminated ~2:1 by successful recycles.

- **Evidence:** Scan of 3,222 transcripts across ~/.claude/projects (780), ~/.claude-secondary (792), ~/.claude-tertiary (804), ~/.claude-quaternary (846). Note ~/.claude-next/projects is a SYMLINK to ~/.claude/projects — the 'four config dirs' are four accounts but only four distinct transcript trees, no double-count. Dated instances of the dead-in-place shape run 2026-07-13 -> 2026-08-11, roughly one every 2 days, with three in the final 24h.
- **Source:** `scratchpad scan over ~/.claude*/projects/**/*.jsonl`

### `[MEASURED][GAP]` The inverse failure (recycling too early) is NOT establishable with the current instrument, and the Hold test that would prevent it is essentially never exercised.

- **Evidence:** 565 `--recycle` invocations measured in transcripts: occupancy at fire min 55,361 / median 285,188 / p90 665,469 / max 909,941 input tokens; 165 (29%) fired below 200,000 occupancy. Whether those are premature is UNKNOWN because fill% needs the window, which lives only in ephemeral /tmp/cc-telemetry/<sid>.json. Hold-test language ('the Hold test', 'context IS the asset', 'do NOT cut it') appears 9 times across 8 of 3,222 sessions (0.25%) — no evidence of bypass, and no evidence of application either.
- **Source:** `scan of ~/.claude*/projects/**/*.jsonl`

### `[MEASURED][GAP]` A second, adjacent failure the same evidence exposes: the session that WROTE the memory file closed cleanly at 695,941 tokens occupancy without recycling, and parked a 4-hour cc-await-ping watcher.

- **Evidence:** Session 25855495 (the memory file's own originSessionId) records 1632-1634: `cc-await-ping --timeout 14400` backgrounded at 2026-08-10T22:58:51Z, then a closing assistant turn at 695,941 occupancy announcing the new memory entry, then nothing. It did not apply its own lesson. This is 'never idle waiting on the user because you are low' rather than the announced-never-fired class, but it shares the root: the escape is expensive enough that a session at high fill rationally defers it.
- **Source:** `~/.claude-secondary/projects/.../25855495-ccf0-4f3f-ad8d-5566dfac5565.jsonl:1632-1634`

### `[CLAIMED][GAP]` The repo's own comment already states the actuator's historical hit rate, and it corroborates the arm-gate diagnosis.

- **Evidence:** hooks/waiting-recycle.sh:43 — '0/2419 prod fires decomposed as 1977 not-armed'. Same shape as my live measurement 4,465/5,380 blocked at the arm gate. This is the repo CLAIMING about itself, but it agrees with an independent measurement taken 16 days later.
- **Source:** `hooks/waiting-recycle.sh:43`

## Unknowns

- The fill% denominator. Every occupancy figure above is raw input_tokens; the window is unrecorded, so 'fired at 285K median' cannot be converted to a fill%, and the 165 sub-200K fires cannot be adjudicated as premature or correct. This blocks a quantitative answer to item 5.
- WHY the firing turn's record is absent from a successful --recycle transcript. I INFER the /exit interrupt kills the process before the assistant message is flushed, based on the fire log proving the fire ran ~50s after the brief. I did not confirm it against the harness. If instead something EXTERNAL is recycling pane 113 (it was recycled twice in 3 hours, both times ~60s after a brief appeared), then the two 'successes' are rescues, not self-recycles, and the model-side failure rate is higher than reported here.
- The true announced-vs-fired denominator before 2026-08-09. emit_recycle_event landed only ~2 days ago, so every case before it is unmeasurable in either direction — 12 of the 14 dead-in-place candidates fall in that blind period.
- Whether the memory file's two named payload gates (pane-id-lint reading 8-hex git shas as truncated pane ids; the F3 back-channel gate refusing a brief that says cc-notify cannot reach it) are still live obstacles to hand-refiring an orphaned brief. I did not test them.
- Whether any scanner looks for the pair (predecessor absent + its recycle brief still in /tmp). Three such briefs sit in /tmp right now — fire-lead-recycle.txt, fire-land-arch-shepherd.txt, fire-shepherd-recycle.txt — and two of the three are now known to be spent, so the pair alone would be a false-positive-heavy signal without the fire log to join against.
