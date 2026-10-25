# Critique: D3-schema-first, incident-replay lens

Design under review: `designs/D3-schema-first.md` (cited `D3:n`). The lens: replay the B13 incident step by step against D3. At which step does the idle break, by which mechanism, and is that mechanism a hook (deterministic) or text (advisory)? Would 290215743799 have been filed? Would a ruling have been re-asked? How certain is the fix against a lead that also writes "No round 27 until you answer"?

Abbreviations follow `maps/incident-replay.md`: `TX:n` = line n of the B13 transcript, `IDL` = `~/.claude/autonomy/idl.jsonl`. Code paths are in this worktree.

Everything here was read only. Deviation: one scratch file, `/tmp/b13scope.txt`, was written outside the repo to grep the TX:14 scope line. Nothing under `~/.claude` was written.

---

## 1. Bottom line

On the most likely path, D3 breaks the idle at **F1, 06:44:40Z**. The cause is a **Stop-hook block** from the new `scope_floor()` in `hooks/session-continue.sh` (D3:456-519). The block fires deterministically. Its effect is advisory: it tells the model to run round 27, and nothing makes it.

That path needs two things to have happened earlier:

- **At 02:36Z, the lead filed decision 1 as class B or A, or as a part-gating class C that does not name the loop.** That choice is advisory. D3 pushes it hard, through help text, the refusal, a ready class-B command and the ruling hint, but does not force it.
- **The intake capture put TX:14's loop scope in the store under the lead's sid.** That step is deterministic. I measured that TX:14 has the shape D3 needs (§2).

If the lead ignores both F1 blocks, the latch is spent within seconds and F2/F3 get nothing. The supervisor then **wakes the session itself, deterministically, by 10:11:50Z at the latest**: about 8 h before the operator's 18:11Z message. What the woken turn does is again advisory.

Two paths keep today's idle, and they are the ones a lead that believes "round 27 waits on the answer" is likely to take:

- **Hard category with `--gates all`, `escalation` above all:** no block, no challenge, no nudge.
- **`pick` or legacy with `--gates all`:** one challenge, and its first discharge is a one-line prose answer. The lead's own hold sentence is that answer.

**Estimated** chance that D3 prevents a B13 recurrence: about 65% for the incident lead as it behaved, and about 45% for a lead that also holds in prose. Method: judgment over the branch tree in §3, anchored on TX:4199 (the lead believed round 27 was gated before any ⛔ machinery existed) and TX:4495 (one operator question flipped it at once). A wake before 18:11Z is near-certain on every path that has visible ungated work, except the hard-category path.

---

## 2. Step-by-step replay

| Step (UTC) | Today | With D3 | Mechanism | Deterministic? |
|---|---|---|---|---|
| 02:35 `cc-decide open --help \| head -25` (TX:4249) | "unknown arg --help" (TX:4250) | `-h\|--help` prints `usage()` (D3:92). `usage()` prints the file header from line 2 (`bin/cc-decide:93`). So the lead sees D3's new class text: "B … a judgment call with a status-quo course (the frozen scope, today's behaviour)" and the C category list (D3:256-266). It sees this **before** filing | CLI text | Advisory. §12 does not credit it, but it is the most effective advisory change in the replay: the lead asked for exactly these definitions and got an error |
| 02:36:16 decision 1, `open --class C` with no new flags (TX:4254) | Packet e869 written | rc 2, no file. `tail -3` shows the LIKELY ALREADY RULED line for eb3dbe1e5e94, the class-B command and the class-C fix (D3:133-141). That holds only if the hint ran inside its 3 s bound (defect 7) | CLI refusal | The refusal is deterministic. What the lead re-files is advisory |
| 02:36:27 decision 2 (TX:4260, `tail -2`) | Packet 290215743799 written | Refused the same way. `tail -2` shows only the two commands. The a247 hint and any grant hint sit above the window (D3:1016). The grant does not exist yet: its `issued_at` is 18:11:47Z (D3:721) | CLI refusal | Same |
| First no-sentinel Stop after deploy | n/a | `dod_intake` captures the first `Scope (frozen):` line under `session=666022fd…` (D3:541-553, 616-629). **Measured:** TX:14 is `type:"user"`, `origin.kind:"human"`, the first qualifying record, and its scope line matches D3's loop regex (awk replay of D3:347 printed `MATCH`) | Hook side effect | Deterministic |
| 02:36:51-05:02 closes, lanes landing | ⛔ accepted | Rung 🔧 (custody) or 🔧 "Decision open, not gating", then 📦 while the land is in flight. `SCOPE_FLOOR=none` (`in-flight-custody` / `in-flight-land`, D3:424-426) | Ledger | Correct, control C1 |
| **06:44:40 F1** (TX:4437) | ⛔. session-continue returns silently at `:1103` | **Path B/A** (decision 1 as class B or A): rung 🔧 from the loop arm, `SCOPE_FLOOR=drive`. Then mechanical arm rc 1 (no own dirt), ship floor passes (not 📦/🚀), scope floor **blocks**. No kill phrase (`KILL_RE`, `session-continue.sh:386`, against TX:4114/4163). Fill 64% < 73. The watcher argv names only `~/.claude/bin/cc-await-ping` (TX:4434), a config-root path, so `sb_busy_jobs` does not count it as work (`hooks/lib/session-busy.sh:166-186`, `:274-357`; estimated from the rule). **Path P** (part-gating C): the same. **Path L** (pick or legacy, gates all): ⛔ `challenge`, one block. **Path H** (hard category, gates all): ⛔, `gates-all-hard`, nothing | Stop hook | The fire is deterministic. The effect is advisory |
| 06:45 re-Stop after a block | n/a | A resisting lead re-Stops within seconds. **Measured analogue:** all 12 ship-floor `fired` rows in today's IDL were followed by a `ship-floor-latched` Stop for the same sid 5-34 s later (`grep '"hook":"session-continue"' idl.jsonl \| grep ship-floor`). So both drive fires (`CC_SCOPE_FLOOR_MAX=2`, D3:506) are spent at about 06:45. D3:1035 says the second fire lands at F2; it does not | Hook latch | n/a |
| 07:39:47 F2 / 08:34:59 F3 (TX:4458, 4476) | Accepted | Same HEAD:trunk, so `scope-floor-latched`. The watcher stop and the orphaned `cc-await-ping … &` (TX:4469) are not addressed (D3:1082-1083) | none | n/a |
| 09:11:08 first STALL? after F1 (IDL, measured) | Page to a dead desk | `nudge_subject` #1. If the orphan watcher is alive, cc-notify returns `wake-path-armed` and nobody wakes. The marker is set to re-check in 1 h (D3:677-678) | Daemon | The send is deterministic; whether a wake follows depends on the orphan |
| 10:11:50 STALL? (IDL rows 10:09:09-10:15:48, measured) | nothing | Nudge #2. No watcher is left, so the socket wakes the session (cc-wake W1-W5, `maps/wake-path.md:150-171`). The drain surfaces both lines | Daemon + socket | **The wake is deterministic.** What the turn does is advisory |
| about 14:11 | nothing | Nudge #3 (backoff 4 h, D3:669; STALL? rows continue to 15:16) | Daemon | Same |
| 18:11:47 operator (TX:4488) | Wakes it | On path B/A, round 27 has been running since about 06:45Z | n/a | n/a |

**Where the break happens:** at F1, by the session-continue `scope_floor` drive block, on paths B/A/P. If that is ignored, by the supervisor socket wake between 09:11Z and 10:11Z. On path L, F1 gets one challenge and the wakes carry the same prose escape. On path H, nothing happens.

---

## 3. The branch that decides it: what the lead re-files at 02:36Z

Evidence for each branch, with estimated weights (judgment, not measured):

- **B/A, about 0.6.** The help text names "the frozen scope" as a status-quo course (D3:258-260). The refusal's LIKELY line names a ruling whose default fired: "keep looping until dry (the scope as written)" (`decisions/eb3dbe1e5e94.json`, read with `jq`). The lead later filed exactly this class-B shape by hand once it was shown the analysis (b4780d7bb60e, `maps/incident-replay.md:236`).
- **L/P naming the loop, about 0.3.** At 02:25:42Z, while the rung was 🔧 and no packet existed, the lead wrote "I won't start round 27 until you've decided on the stop rule" (TX:4199). The lead believed round 27 was gated **independently of the ⛔ machinery**. Shown `--gates all|'<the item it blocks>'` with `all` first (D3:138), it declares `all` or `"round 27"`. Defect 3 shows that `"round 27"` ends on the challenge path too.
- **H, about 0.1.** `escalation` reads as "hand this to the operator", and its definition is open-ended (defect 1).

Branch outcomes (estimated): B/A succeeds about 0.9 (F1 block, then up to 3 nudges). L succeeds about 0.4: the challenge text's scope-change sentence (D3:536) is on point, but the discharge is prose. H succeeds 0. The weighted result is about 0.66.

For the prose-holding lead I shift the weights to about 0.4 / 0.4 / 0.2 and lower compliance on B to about 0.65, which gives about 0.45.

---

## 4. Would the lead have filed 290215743799? Would it have re-asked a ruling?

**290215743799: yes, in a faithful replay.**
- The only prior was a247b7288149, which is TrueMemory-scoped. The lead had already found it and discounted it (TX:4235; `maps/ruling-discovery.md:13-20`).
- D3's hint for a247 (ratio 1.62) and the grant hint both print above the `tail -2` window (D3:1016).
- The grant record postdates the filing (D3:721, `issued_at 2026-10-24T18:11:47Z`).
- Under D3 the lead would re-file it as class C `escalation`, since D3's own definition lists "data egress outside a standing grant" (D3:264), with a part gate, or as class B with "keep the review all-Claude" as the default. Either way it does not gate round 27 in the lead's own view: "No round 27 until e869fac7eb34 is answered" (TX:4270) names only decision 1.

**In a recurrence after the grant lands:** the S bullet (D3:891) and the grant hint make an ask unlikely. But `xvendor-review.sh` will meet the same auto-mode classifier refusal as at TX:4678 ("Permission … denied by the Claude Code auto mode classifier. Reason: [Data Exfiltration]"), which also refused the tiny "reply OK" probe (TX:4683). So the grant turns into a permission ask, a hard category. If that ask is declared `--gates all`, it kills the floor for the whole session (D3:417).

**Re-asking a ruling: decision 1 would probably still be asked, but as class B.**
- D3 never refuses on similarity (D3:1066). The hint appears only once the lead has already decided to ask (`maps/ruling-discovery.md` §5.2). The operator's 02:22Z message ("is this forever?", TX:4114) is new input that a lead can fairly read as reopening eb3dbe1e5e94.
- A class-B re-ask whose default is the ruling's own course is harmless.
- D3's success here comes from the class choice, not from ruling discovery.

---

## 5. A lead that also writes "No round 27 until you answer"

D3 is keyed on the ledger, not on prose, so the prose neither triggers nor suppresses a block. That is correct: the replay map shows prose cannot tell an honest ⛔ from a hold (`maps/incident-replay.md:28`, `:447`).

What the prose predicts is the branch. A lead that holds in prose believes the decision gates the loop, and D3 gives that belief two exits that stop with no state change:

- the challenge's "reply with one line naming that step and stop" (D3:537);
- the nudge's "say which act in one line, and stop" (D3:693-694).

"No round 27 until e869fac7eb34 is answered" (TX:4270) already is that one line. Against this lead, D3's ceiling is 2 drive blocks or 1 challenge, plus 3 nudges, all advisory.

---

## 6. Defects

See the structured return for severity. Evidence and fixes in brief:

1. **`escalation` is a hard category that no check audits.** It is in `ghard` (D3:153-154). It is missing from the gate-classify cross-check, which covers only `self-mod,money,permission,credential,destructive` (D3:241-243). Its definition, "a surface a rule or the repo's CLAUDE.md reserves" (D3:262), is open-ended. agentsync's own "Escalation surfaces" section lists none of the B13 questions (`agent-context-sync/CLAUDE.md:81-84`). Hard plus all gives `SCOPE_FLOOR=none` (D3:417), so no challenge and no nudge (D3:663): today's idle, with its packets correctly filled in.
   *Fix:* when `UNGATED>0`, **any** gates-all packet, hard or not, gets the one challenge, discharged only by a state change. Add `escalation` to the cross-check. List `'<the item it blocks>'` before `all` in the recipe.
2. **The challenge is discharged by a sentence.** D3:537 and D3:693 contradict the stop-hooks constraint "A prose sentence is not a discharge" (`maps/stop-hooks.md:134-136`). D3 itself states that constraint (D3:171) and then breaks it.
   *Fix:* allow only `--supersedes` or `regate <id> --gates all --why-gated "<the step that builds on it>"`. When the §2.8 status-quo regex fires (it fires on e869's `no::keep running rounds`, D3:251), use drive, not challenge.
3. **A part gate that names the loop gives a self-contradictory drive.** The ledger never compares `BLOCKED_GATES` with `LOOP_HEAD` (D3:378-379, 413-428). With `--gates "round 27"`, the drive reason says "run the next round as scoped … never build the gated act itself" and offers `regate … --gates all … and close` (D3:524-528). That path ends on the challenge.
   *Fix:* when `LOOP_OPEN=1`, a gate text naming the loop's iteration (round, iteration, next round, loop) is treated as "the scope it would change", so the floor drives and the reason says so.
4. **The supervisor's oracle skips the hook's abstains.** `nudge_subject` reads the ledger's `SCOPE_FLOOR` from the operator-readout row (D3:659-663). The kill-switch, assignee, teardown, context-high and busy abstains exist only in `scope_floor()` (D3:481-498). So after an operator "…and stop" (`KILL_RE`, `session-continue.sh:386`), the hook stands down and the supervisor then sends up to 3 "drive the next in-scope step now" wakes. That is a false wake against an explicit operator stop.
   *Fix:* gate the nudge on the last `session-continue` `scope-floor*` IDL row as well. Skip on `kill-switch`, `assignee`, `teardown`, `context-high` and `busy`.
5. **The replay misstates F2 and F3.** D3:1033-1036 says the second drive fire lands at F2. The measured re-Stop interval after a floor block is 5-34 s (12 of 12 ship-floor fires, IDL), so both fires are spent at about 06:45. F2 and F3 are new watcher-timeout turns that get nothing, and nothing pushes between about 06:45 and 09:11Z.
   *Fix:* correct §12. Optionally allow one more fire on a turn that a wake started (not a block-continuation), bounded by `CC_SCOPE_FLOOR_TOTAL`.
6. **The refusal header falls outside `tail -3`.** It is line 1 of 5 (D3:134-138), and the pipe masks rc 2. The lead sees three hint-looking lines and no id.
   *Fix:* the last line begins `cc-decide: NOT FILED —`.
7. **The ruling hint fails open under the load the lead actually ran at.** The bound is 3 s, against 0.73 s measured on a quiet box (D3:212-215). At 02:36:56Z Stop hooks were running 1.8-4.8 s (TX stop_hook_summary: completion-assert 4727 ms, operator-readout 4770 ms). The LIKELY line that §12 leans on (D3:1005) is the part most likely to drop out.
   *Fix:* a precomputed index of answered packets, or a longer bound on the refusal path only.
8. **The decision-2 replay is anachronistic and optimistic.** See §4: the grant postdates the filing, the hints sit above the `tail -2` window, and the classifier refuses the entrypoint.
9. **The loop end marker does not cross a recycle.** `dod-persist get`, which serves the /handoff DoD carry, returns only `Scope (frozen):` lines (`hooks/dod-persist.sh:140`, `:503-516`). After `Scope (done):`, a successor's brief still quotes the loop. Intake then captures it under the new sid, and `compute_loop_floor` reads only that sid's lines (D3:348-353). So a finished loop is driven again.
   *Fix:* honour the lineage's newest `Scope (done):`, and have `get` print it.
10. **D3's case for intake reading the "first" line rests on a claim the replay does not support.** D3:626-629 cites "the newest transcript line is a lane brief". The existing PreCompact extractor reads only `text` blocks (`hooks/dod-persist.sh:143-149`), and replayed on TX lines 1-4487 it returns only TX:14 (measured: same jq, `grep -aoE 'Scope \(frozen\):.*'`). The intake mode partly duplicates `extract_scope`. That is harmless, but the stated rationale is wrong.

---

## 7. Best ideas worth grafting

- `open --help` that works and prints the class definitions (D3:92, test D17). The B13 lead asked for help before filing (TX:4249-4250) and got an error.
- The class-C refusal prints, last and fitted to `tail -N`, a ready class-B command built from the caller's own arguments (D3:126-143).
- A `gates` field with a read-side `gates_all` fold, where an absent field means all, so legacy packets keep today's ⛔. The ledger tests it with `has()`, not `//` (D3:150-155, D3:311-314).
- A session-scoped loop-scope floor with an explicit `Scope (done):` end marker (D3:332-369). The intake capture from the first human record is measured to hit TX:14 (D3:541-557, 616-629).
- A drive latch keyed on (sid, sorted open C ids, loop head), reset only by HEAD or trunk progress, with a total cap. It fails closed when the latch file cannot be written (D3:500-515).
- A busy probe under load that reads a timeout as "unknown" and proceeds (D3:488-499).
- `nudge_subject`: direct `cc-notify`, never `page()`; `.nudged` survives `clear_page`; backoff, with a 1 h re-check after `wake-path-armed`; the verdict-parse fix also applied to `advise_subject` (D3:648-710).
- `--supersedes` as a state-change discharge with sid, hard-category and producer guards (D3:169-199).
- The scope-change sentence: "a question that would change the frozen scope gates none of it" (D3:822, D3:536).
