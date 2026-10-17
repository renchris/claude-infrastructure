# Slot E: the TeammateIdle hook timed out (`hooks/teammate-auto-shutdown.sh`)

Read-only investigation. The live hook and reap-guard are byte-identical to this worktree
(`cmp ~/.claude/hooks/teammate-auto-shutdown.sh hooks/teammate-auto-shutdown.sh` → IDENTICAL;
same for `scripts/reap-guard.sh`). Timestamps: the hook log is local CDT, transcripts are UTC
(CDT + 5 h).

## 1. What happened at 18:19:34 (quoted evidence)

Teammate transcript
`~/.claude-secondary/projects/-Users-chrisren-Development--worktrees-wt-pool-5/5423f92a-9089-4690-8c85-28ffc4018768.jsonl`:

- line 175: last assistant text at `2026-10-16T23:19:33.311Z` ("WEB-14 has landed on `origin/next16` at `29d6df2` …").
- line 176: `"subtype":"stop_hook_summary","hookCount":13` at 23:19:34.576Z. The 13 Stop hooks were all quick; the slowest was `completion-assert.sh`, `"durationMs":1219`.
- line 177: `"attachment":{"type":"hook_cancelled","hookName":"TeammateIdle",…,"command":"~/.claude/hooks/teammate-auto-shutdown.sh","durationMs":5030,"timedOut":true,"timeoutMs":5000}`, `"timestamp":"2026-10-16T23:19:39.613Z"`. So the hook started at about 23:19:34.58Z.
- line 178: `turn_duration` 2,308,039 ms, so the member was about 38 min old. That is far past reap-guard's 300 s birth grace (`scripts/reap-guard.sh:60`).

Hook log `~/.claude/logs/teammate-lifecycle.log`. It holds exactly one line for this run:

```
33303:[2026-10-16 18:19:34]   ↳ web-next16: worktree /Users/chrisren/Development/.worktrees/wt-pool-5 is SHARED by 7 members — gating on it, removal refused
```

The next line is another member's. The next web-next16 line belongs to a different mechanism (session-end's orphan closer):
`33306:[2026-10-16 18:26:04] orphan-pane-close web-next16: no shutdown_approved from web-next16 in …/session-3cbb68e5/inboxes/team-lead.json - nothing closed`.

Other evidence that the run never got far:

- reap-guard decision store `~/.claude/reap-guard/`: the only 2026-10-16 record is `reap-web-config-20261016T224108Z-…json`. There is none for web-next16. Every `cmd_decide` exit path writes a record before it returns (`scripts/reap-guard.sh:188,193,203,206,210,228,252,260,266,272`), so reap-guard either never started or was killed before it decided.
- `~/.claude/watchdog/teardown/` has no `5423f92a…json` marker. `close_and_log` writes that marker before any close (`hooks/teammate-auto-shutdown.sh:382`), so the close path was never reached.

**Where the line sits in the code.** It is written at `hooks/teammate-auto-shutdown.sh:1007`, the shared-cwd leg of worktree resolution. Every later path writes at least one more line before it exits: defers at :1015/:1109/:1129/:1232/:1246/:1272, SURFACE at :1241/:1276, the reap marker at :1290, holds at :656/:1448/:1463. So a run whose last line is :1007 was killed in the gate section, between :1014 and the reap-guard call at :1205. It was not silently refused.

Load at the time, measured: `~/.reso/limit-recover/upgrade/5423f92a-20261016T232405Z/events.jsonl:1` shows `load1=21.15` at 23:24:05Z, and `:2` shows `load1=20.10`.

## 2. What the hook does, and what it would have done for web-next16

Control flow in file order (all `hooks/teammate-auto-shutdown.sh`):

1. Parse the payload: `teammate_name`, `team_name`, `session_id` (:788-791). **`transcript_path` is never read.**
2. Resolve the worktree. The legs are manifest (:834-859), team config (:867-877), member-named worktree (:890-932), TSV (:938-948), /tmp (:951-981), and the shared team-config cwd (:995-1011). wt-pool-5 resolved by the last leg: SHARED by 7, `WORKTREE_OWNED=false` (:1007).
3. Gates:
   - `.teammate-busy` (:1014).
   - Dirty tree via `git status` (:1039), plus per-file attribution on a shared cwd (:1070-1095). This calls `_find_transcript` at :1077, but only when the tree is dirty.
   - Tool-in-flight (:1128). `_tool_in_flight` calls `_find_transcript` (:677), then runs `jq` over the whole transcript 2-3 times (:691, :727, :769).
   - `reap-guard decide` (:1205). It runs as a separate bash and calls `rg_find_transcript` again (reap-guard.sh:182 when young, :250 always, because `--session-id` is passed) plus `ce_last_interactive_age`.
   - Unresolved-worktree fail-closed (:1267).
4. Reap: log (:1290), checkpoint plus assert on the ref (:1294-1315), fallback patch (:1326-1340).
5. Resolve the pane id from team-config `tmuxPaneId` (:1350-1364), with an env fallback (:1371-1379).
6. Operator-adoption belt (:1399-1473). This is `_find_transcript` **again** (:1431), plus `cc-sessions --json` inside `_spawn_epoch` (:599).
7. PPID-forensic log (:1480), then `{"continue": false}` on stdout (:1483), then `pin_term_verdict` (:1516-1531).
8. Detached `( sleep 3; close_and_log …; worktree remove if owned ) &` (:1537-1568). `close_and_log` writes the teardown marker (`mode=teammate-idle`, :382), closes via `it2 session close -f -s <pane>` with kitty identity pins (:207-222), and confirms the pane is gone by checking it is absent (:410).

**Projected outcome for web-next16 (inferred).** It would have been REAPed through `shared-no-refs` or `shared-finished-turn`:

- The tree was gated as shared.
- The last record was an assistant TEXT turn end, so the tool-in-flight gate would not fire.
- Age was about 2,300 s, past the grace.
- No refs exist for the member. Measured: `git -C wt-pool-5 for-each-ref 'refs/wip/web-next16/**' 'refs/checkpoints/web-next16/**'` printed nothing, so `has_products` is false, which gives `shared-no-refs` (reap-guard.sh:226-233).
- No operator prompt is known (R-d). UNVERIFIED: I did not re-run `ce_last_interactive_age`.

The sibling run 38 min earlier on the same tree and team went exactly that way, and its reap-guard record says `"decision": "REAP", "reason_kind": "shared-no-refs", "age_s": 657`:

```
[2026-10-16 17:41:04]   ↳ web-config: worktree …/wt-pool-5 is SHARED by 7 members — gating on it, removal refused
[2026-10-16 17:41:08] Auto-shutdown idle teammate: web-config (team: session-3cbb68e5)
[2026-10-16 17:41:08]   ~ nothing to checkpoint (tree matches HEAD, or the member wrote nothing) for …/wt-pool-5
```

That sibling run also died: there is no `PPID-forensic` line and no close verdict after it. So the gate section alone took about 4 s (17:41:04 → :08), and the run was killed in the adoption belt or the checkpoint before :1480. This hook is structurally at or over its 5 s budget on this box, not just unlucky once.

For web-next16 the end state would have been: `{"continue":false}`, then 3 s later a forced close of pane 217, with a teardown marker telling lead-crash-watchdog "intentional teardown".

## 3. Why it ran past 5 s

**Root cause: an O(project-dirs) filesystem scan, repeated 3-5 times per run, to look up a path that the payload already carries.**

`_find_transcript` (`hooks/teammate-auto-shutdown.sh:584-593`) does:

```
for r in $PROJECT_ROOTS; do … f="$(find "$r" -maxdepth 2 -name "$sid.jsonl" 2>/dev/null | head -1)"
```

`rg_find_transcript` (`scripts/reap-guard.sh:115-124`) is the same code.

- `PROJECT_ROOTS` puts `~/.claude/projects` first (:97). For a `~/.claude-secondary` teammate that root is a full miss scan, and then secondary is scanned.
- `find … | head -1` does **not** stop early. find only gets SIGPIPE on a second write, and there is only one match, so each root it touches is walked completely.
- Measured: `ls -1 ~/.claude/projects | wc -l` = 18,070 subdirs; `ls -1 ~/.claude-secondary/projects | wc -l` = 18,085; `find <root> -maxdepth 2 | wc -l` ≈ 38-40k entries per root.
- Calls per run: :677 (always), :1077 (shared and dirty), reap-guard :250 (always) and :182 (when young), :1431 (adoption belt). That is 3 on the minimal REAP path and up to 5.
- Measured cost, `bash /tmp/e-seam/ft.sh` running the hook's exact loop for this sid three times: **27.24 s, 25.6 s, 22.6 s** at `vm.loadavg` 373-410 (the load at the time I measured, 19:56 CDT, not at the incident). An earlier single 4-root pass measured 3.24 s (zsh `time`, load 343), so the cost varies a lot with cache and I/O contention. For comparison, a direct `[ -f "$transcript_path" ]` measured 0.121 s including two python starts used as the timer.
- The payload already carries the path. The vendor common envelope for every hook includes `session_id, transcript_path, cwd, permission_mode, hook_event_name` (`docs/research/subagent-lifecycle-2026-09-19/C-vendor-in-process-subagents.md:410-411`), and TeammateIdle adds `teammate_name`, `team_name` (:420). The hook reads only the latter fields (:789-791). `hooks/completion-assert.sh:182` already reads `.transcript_path` in the same Stop pass.

Smaller costs on the same hot path:

- Two or three whole-transcript `jq` passes in `_tool_in_flight`. That is 0.063 s on this 803 KB transcript (zsh `time`), so negligible.
- A second `git status` inside reap-guard (reap-guard.sh:196).
- `cc-sessions --json` (:599, :1185, :1433). Cost UNVERIFIED.
- Forks for `teammate-checkpoint.sh` (:1296).

**No timing instrumentation exists.**

- `grep -n SECONDS hooks/teammate-auto-shutdown.sh` finds nothing. The comments assume a 5 s budget (:141, :1370, :1533) but no code enforces or measures it.
- tests/teammate-auto-shutdown.bats has 71 `@test`s. None asserts wall time (grep for budget/elapsed/SECONDS finds only fixture-timing comments at :88, :416-455).
- The F register already suspected this ("H3 — SUPPORTED, NOT PROVEN", `F-fleet-actuator-teammate-auto-shutdown.md:309-317`) and named "`jq` over every team root" and the checkpoint as the suspects. The transcript `find` was not named there.

**This is the common case, not an outlier.**

- Estimated with `python3 -I /tmp/e-seam/an.py ~/.claude/logs/teammate-lifecycle.log <window>`, which keys on the "last line is :1007" shape: since 2026-10-01, **314 of 407 (77%) shared-cwd runs** have no follow-up line within 6 s (312 within 30 s, 310 within 120 s). So killed runs do not continue after the cancel.
- By day: 10-07 45, 10-09 113, 10-10 32, 10-11 79, 10-15 20, 10-16 11.
- Measured with grep over October lines: 56 `Auto-shutdown` → 44 `PPID-forensic` → 18 `✓ closed pane` + 12 `already gone` + 9 `close FAILED`.
- **No reap line at all between `2026-10-08 00:27:33` (p3-wire) and `2026-10-16 17:41:08` (web-config).**

## 4. Where the timeout is configured

| file:line | content |
|---|---|
| `~/.claude/settings.json:590-598` (a regular file; `~/.claude-secondary`, `-next`, `-tertiary`, `-quaternary` `settings.json` are symlinks to it) | `"TeammateIdle": [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/teammate-auto-shutdown.sh", "timeout": 5 }] }]` |
| `settings-templates/settings.example.json:638-648` | the same entry, `"timeout": 5` |
| install.sh / migrations | no hits for `teammate-auto-shutdown` or `TeammateIdle` (`git grep`, plus a grep of install.sh) |

`timeout` is in seconds. The harness enforced 5000 ms (`timeoutMs:5000`, transcript :177).

## 5. Would success have prevented the incident?

**Very likely yes, with two conditions.**

- If the hook had finished, the pane close would have happened at about 18:19:42, more than 4 min before the 18:24:05 upgrade claim.
- lr-upgrade's census is "one row per live registry row" (`scripts/limit-recover/lr-upgrade.sh:24`, :601). A teammate whose process had already exited is not a candidate. So there would have been no claim, no deliberate teardown, no resume debt, and nothing for `cc-resume-debt` or `boot-resume-launch` to resurrect. UNVERIFIED: I did not trace whether a stale registry row could still be enumerated after the process died.
- The `mode=teammate-idle` teardown marker (:239-255, :382) is what makes lead-crash-watchdog classify that death as intentional rather than CRASH. So the crash-recovery path also stays quiet.

Condition (a): the actuator works. In October the closes split as 18 `✓`, 12 already-gone and 9 FAILED (some rc=124). In September the F register measured 55% (`F-…md:22-25`).

Condition (b): the process actually dies with the pane. All 18 October `✓` lines are followed within 0-1 s by `✗ process survived pane close`. That is probably a race, since the check runs immediately after the close (:420-427), but it is UNVERIFIED.

Even so, this hook was the only mechanism positioned to end the member before 18:24:05. The lead's `shutdown_request` arrived 6 min later (transcript :186, 23:25:38Z).

## 6. Fix options (ranked)

1. **Hot-path fix (the real one): resolve the transcript once, from the payload.**
   - Read `TRANSCRIPT=$(jq -r '.transcript_path // empty')` at :788-791. Accept it only if `-f` and its basename is `$SESSION_ID.jsonl`.
   - Fall back to a cheap derived path, then to `_find_transcript`.
   - Thread it into `_tool_in_flight` (:677), the attribution step (:1077) and the adoption belt (:1431).
   - Add `--transcript <path>` to `reap-guard decide` (reap-guard.sh:150-160), so `rg_find_transcript` (:182, :250) is skipped when the path is supplied.
   - Also make both `find` fallbacks stop at the first match (`-print -quit`), and search the session's own `$CLAUDE_CONFIG_DIR/projects` first.
   - Expected effect (estimated): 3-5 full scans of about 18k directories become 0 per run.
   - Add a bats test with a fake root of thousands of project dirs that asserts the hook never runs `find` when `transcript_path` is valid. Use a PATH-stub `find` that records calls, not a wall-clock assert (see the bats comments at :416-455 on wall-clock flakiness).

2. **Enforce the budget instead of dying silently.**
   - Add `$SECONDS` checkpoints before each expensive gate and before committing to the reap (:1287).
   - Past about 3 s: log `budget exhausted at <gate>` and `exit 0`. Never emit `continue:false` on that path.
   - Queue a `pcq_add` retry row through the existing pane-close-queue (`scripts/lib/pane-close-queue.sh`, already used at :1138-1151). That turns a silent kill into a durable, visible record. This matches the "SECONDS checkpoints that exit 0 silently past 3 s and bump a skip counter" rule in `docs/research/load-hook-timeouts-2026-10-11/DESIGN.md` (Prompt-hook rules).

3. **Modest timeout headroom (10-15 s) only after 1-2.** Change it in `~/.claude/settings.json:590-598` and `settings-templates/settings.example.json:638-648`.
   - On its own this is a band-aid: the scan cost grows with project count and load (one scan measured 22-27 s at load ~400).
   - TeammateIdle runs inside the member's own Stop pass, so a longer budget holds that pass longer.

4. **Do NOT use `async: true`.** DESIGN.md "Designs rejected" says it has no enforced timeout and runs pile up. It would also drop the `{"continue":false}` output.

5. **Structural follow-up: decide in the hook, act detached.**
   - Move the checkpoint, the adoption belt and the close into a single-flight, setsid-detached worker (`scripts/lib/detach.sh`) with its own deadline. The worker must re-check tool-in-flight right before it closes.
   - Today's `( … ) &` (:1537-1568) is *not* setsid. detach.sh:7-12 documents that Claude Code SIGKILLs a tool call's whole process group; whether the same group-kill applies to a timed-out hook is UNVERIFIED (F-register H3).

## UNVERIFIED

- The exact statement inside :1014-:1205 that was running at the kill. Pinned only by elimination: no log line, no reap-guard record, no marker.
- Whether wt-pool-5 was dirty at 18:19, which decides whether the :1077 attribution step, and its extra find, ran.
- That TeammateIdle on 2.1.293 still carries `transcript_path`. It is documented from a 2.1.260 binary read (C-vendor :410-411) and not re-read here.
- The R-d (operator-adoption) verdict for web-next16, the cost of `cc-sessions --json`, and the cache and I/O state at 18:19. The find timings were taken at load ~340-410, not at the incident's ~21.
- Whether the 18 "process survived" lines are real survivors or a timing race.
