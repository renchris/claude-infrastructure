# A03 — SKEPTIC pass (2026-09-08, ~23:00Z, read-only)

Everything marked **measured** I ran this session (commands inline). "lead-measured" = from the
plan § Lead probes / backlog row evidence. "binary" = read out of claude.exe 2.1.260 by byte offset.

## Numbers re-checked

| claim | axis | re-run | holds |
|---|---|---|---|
| env=1 adds exactly TaskCreate/TaskGet/TaskList/TaskUpdate; control has none; TodoWrite absent | yes | **measured** `claude.exe --print --model claude-opus-5 --effort low --setting-sources "" --output-format json --permission-prompts none '<enumerate tools>'` from /tmp/a03-skeptic, `env -u` control ($0.075) vs `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` ($0.048) | yes |
| 5/5 config dirs' tasks/ realpath to ~/.claude/tasks | yes | **measured** python realpath ×5 | yes |
| four settings.json inodes | 819585538/845469692/819585582/819585610 | **measured** `stat -f '%i %z'`: 819585538 41,763 · **846310556 38,801** · 819585582 40,946 · 819585610 38,803 — secondary was rewritten since; still four inodes | yes |
| 293 open / 58 lists / 85% >30 d / 89 >90 d / 40 >180 d / median 41.2 / oldest 228.6 | yes | **measured** python walk: 293 / 58 / 248 / 89 / 40 / 41.3 / 228.7 | yes |
| cim 66 open, 35 >30 d | yes | **measured** 66 / 35 | yes |
| 10 open items with metadata.owner_session | yes | **measured** 10 | yes |
| "1,527 task JSONs (803/212/81)" | 1,527 | **measured** 1,096 task JSONs (803+212+81) + 424 `_summary.json`; 1,527 = 1,096 + the 431 summaries | **no — summaries were counted as tasks; status counts are right** |
| 994 list dirs, 219 doubled | 994/219 | **measured** 991 / 219 (3 dirs swept meanwhile) | yes |
| 73 ms jq over cim raw JSONs | 73 ms | **measured** 44 ms (`time jq -s …`), 37 ms via _summary | yes |
| task-completed-index.sh registered nowhere | yes | **measured** grep -c across all four settings.json = 0/0/0/0; repo hits are docs only | yes |
| TaskCreated registered nowhere | yes | **measured** jq over hooks in all four: only `PostToolUse TaskCreate\|TaskUpdate → task-mutation-index.sh` and `TaskCompleted * → task-quality-gate.sh` | yes |
| backlog ebe84950e98a is BLOCKED | blocked | **measured** `cc-backlog list --all --json`: **status done**, closed 2026-09-08T22:14:32Z by session b418b97a (the lead) | **no — already closed** |
| ~/.zshrc:88 `_cc_tlid` = `<toplevel basename>-<branch>` | yes | **measured** sed -n 88p | yes |
| all four Task tools `shouldDefer:!0` | yes | **binary** TaskCreate def: `userFacingName(){return"TaskCreate"},shouldDefer:!0,…,isEnabled(){return O9()}` | yes |

## Mechanisms the axis inferred or left open — now read from the binary

1. **TaskCompleted fires on a plain solo `TaskUpdate status:completed`** (axis open question): `c_t(...)` is
   called inside TaskUpdate's body at @164048696 — `if(d==="completed"){let de=[],be=c_t(e,re.subject,…)`;
   blocking errors return `{success:false}`. A second call site @164283858 fires TaskCompleted at **Stop**
   for every `in_progress` task owned by the current agent, gated on `Ji()` (dynamic team context) —
   teammates only. Rec 5 is therefore viable for solo sessions.
2. **Id allocation is locked** (axis "did not measure"): `bXn` (create, @159796324) acquires a
   proper-lockfile via `Ms(Te(e),N)` where `Te()` creates `<list>/.lock` and `N={retries:30, 5–100 ms}`;
   next id = `max(readdir max, .highwatermark)+1`; the v5-storage branch additionally writes with an
   `ifAbsent` precondition and retries 16 ids. **measured**: 46 list dirs carry `.lock`, 23 carry
   `.highwatermark`. Failure under contention is a thrown "[Tasks] Failed to create" — loud, not lost.
   Lead-measured 22:12Z: two concurrent `-p` sessions, ids 1–6, nothing lost. Rec 6 is discharged.
3. **`.owners/` sidecar is safe from the binary**: `aC` (list) filters `u.endsWith(".json")`; the reset
   path `yXn` filters `!f.startsWith(".")`. Our own helpers glob `[0-9]*.json` / `*.json`. Not checked:
   `scripts/worktree-gc*.sh`, which reference `.claude-tasks`.
4. **No adoption prose in the binary**: `# Task Management` 0 hits, `Use the TaskCreate` 0 hits; the only
   TaskCreate prose is two input-repair messages. Rec 2's premise (enable ≠ use) stands, unmeasured.
5. **Interactive gate**: same `isEnabled(){return O9()}` for both modes; the lead's own interactive
   2.1.260/opus-5 session confirms ABSENT with the flag unset (row `needs` text). No interactive
   positive control (flag ON, interactive) exists yet — inferred from shared code path.

## Missed by the axis (its question required these)

- Recs 3 and 5 list ONE settings.json; the house convention (migrations/0021-fleet-hook-parity.sh:98)
  iterates all FIVE config dirs — the axis flagged exactly this asymmetry for rec 1 and then repeated it.
- Rec 4 rides `scripts/wrap-ledger.sh`, which A01 measured at 14.3 s uncached in this repo against
  completion-assert's 5 s Stop timeout (lead-measured, A01). The 44–73 ms jq is not the cost that decides
  whether the rung is observable at Stop; the memo's warmth is.
- Waves are fired by `scripts/handoff-fire.sh`, which sets **no** `CLAUDE_CODE_TASK_LIST_ID`
  (**measured** grep: 0 hits); the fired pane's launcher then derives `<worktree>-<branch>`. The
  wave-sharing fix is a pass-through in handoff-fire, not a shell-profile edit (rec 8).
- The model self-report instrument is noisy: the lead's single env=1 run did NOT list TaskCreate (plan
  line 91) while the axis's and my runs did. Two of three runs agree; the schema-level check is the
  reliable one.
- Rec 7 and rec 6 were already driven by the lead before this skeptic pass (row done 22:14:32Z).

Files read, no file other than this one written; no process killed; nothing committed.
