---
status: closed
created: 2026-08-11
owner: desk
---

# Do the recycle/handoff actuators actually fire, and are they running HEAD bytes

*Axis `actuators` of the context-economy 100th-percentile assessment `wf_5e9f820e-438`. Verdict: [`../context-economy-100p-2026-08-11.md`](../context-economy-100p-2026-08-11.md).*

**At 100th percentile:** `NO`

**Verdict.** The bytes are perfect and the wiring is uniform, but the actuators are effectively silent — 33,667 waiting-recycle evaluations produced 8 advisory nudges and zero recycles, boundary-handoff fired 0 times in 1,319 evaluations, and the one auto-exec path has not run since 2026-08-01 because it is armed for a config-dir/cwd pair no session in the fleet occupies.

**Load-bearing claim.** The rails are perfectly deployed and completely wired, and they still cannot fire: waiting-recycle abstains 78% of the time on `not-armed` because its arm-by-default keys on a `desk` role file that does not exist while the fleet's live role is `orchestrator`, and its one auto-exec arm is keyed to a config dir zero sessions use; boundary-handoff, the only rail on every session, has fired 0 times in 1,319 evaluations because T=73 on a 1M window means 730,000 tokens that this fleet never reaches, and the 150 evaluations that DID clear the threshold were then silenced by a shared gate-green marker sitting 62 commits behind HEAD.

**Shortest fix.** Three edits, in cost order. (1) Add a window-independent ABSOLUTE-TOKEN axis to boundary-handoff, exactly parallel to the size axis it already has: alongside SIZE_MB/RSS_MB at hooks/boundary-handoff.sh:105-106 add `TOK_K="${CC_BOUNDARY_TOK_K:-250}"` and fire when `.input_tokens` (already written by statusline.sh:136) exceeds it, with a +50K re-arm dimension in the :335-355 latch. This is the only threshold that survives a 200K-vs-1M window and it matches the measured memory cost model, which is linear in resident tokens not in window setting. (2) Make waiting-recycle's arm reachable: either set `CC_WR_DESK_ROLE=orchestrator` in the five settings.json env blocks, or `touch ~/.claude/cc-roles/desk` with the desk's sid — one of these turns 26,128 not-armed abstains into evaluations. (3) Demote gate-not-green-at-head from a hard abstain to a wording change in the advisory (hooks/boundary-handoff.sh:317): the marker is shared across every worktree of the repo and only a background daemon advances it, so as written it hands one stale daemon a veto over the fleet's entire context economy.

**Skeptic: REFUTED** (confidence high)

> REFUTED on its load-bearing causal mechanism; the symptom numbers survive, the diagnosis does not, and one of the two named causes is empirically false.

WHAT SURVIVES (independently re-measured, not inherited):
- boundary-handoff: 1,341 evaluations, 0 fires. waiting-recycle: 34,069 abstains, 8 "fired", 20 gc — and all 8 "fires" are `busy-nudge:dirty-tree-hold`, i.e. advisory nudges, zero recycles. Deployed bytes ARE HEAD (`git diff --stat origin/main -- hooks/boundary-handoff.sh hooks/waiting-recycle.sh scripts/wrap-ledger.sh` is empty; both live paths are symlinks into the checkout, checkout on `main`). Stop-hook wiring IS uniform (boundary-handoff registered in all four `settings.json`). The gate-green marker IS exactly 62 commits behind HEAD. Verdict NO survives.

WHAT IS REFUTED:

1. "T=73 on a 1M window means 730,000 tokens that this fleet never reaches" — FALSE, and the error is a population that excludes the failing case by construction. MEASURED: 6 distinct transcripts crossed 730,000 resident tokens in the last 5 days (max 838,573); 41 crossed 500K; 123 crossed 350K, over 1,529 deduped transcripts across all four config roots. The only evidence that could have produced "never reaches" is the `below-threshold:N<73` abstain records themselves — an algebraic restatement of the threshold, and a population that CANNOT contain a ≥73 reading, because a session at ≥73 does not emit that record at all.

2. T=73 is not even the binding threshold. A sibling arm in the SAME FILE lowered the effective floor to 35 on 2026-08-03 (`T_FREEWIN=35`, hooks/boundary-handoff.sh:259, commit ab6d3d1e5) — 369 of the 845 below-threshold records sat at used≥35. The claim attributes the silence to a threshold a sibling mechanism had already superseded five days before the earliest record it cites.

3. "arm-by-default keys on a `desk` role file that does not exist while the fleet's live role is `orchestrator`" — half-true, and its implied remedy is inert. `~/.claude/cc-roles/` holds exactly one non-archive entry, `orchestrator`, and it is ZERO BYTES. hooks/waiting-recycle.sh:220-229 states the invariant explicitly ("set-but-empty is a DISTINCT state from unset — an empty role file must still return 1"). Renaming DESK_ROLE to `orchestrator` changes nothing: no role file in this fleet carries a uuid/sid to match. Separately, 4,331 abstains (12.7%) are `disarmed` — an explicit per-desk kill-switch, i.e. a deliberate refusal, not broken wiring.

4. "0 fires in the hook's entire lifetime" / the raw counts — the IDL is ROTATED (8 `.gz` in ~/.claude/autonomy/). Even concatenating live + all 8 rotations, the oldest boundary-handoff record is 2026-08-08: a 3.5-day window, not a lifetime. Their 1,319/33,667 undercount the concatenated 1,341/34,097, consistent with a partial-rotation read.

5. Latent sampling defect their four-dir census almost certainly shares: `~/.claude-next/projects` is a SYMLINK to `~/.claude/projects`. A plain `find` over the four config dirs (no `-L`) returns ZERO files for .claude-next — silently dropping the primary account's 453 recent transcripts, the largest population. I hit this myself and corrected it.

THE CORRECTED CAUSE (strongest form, and stronger than the claim):
Every one of the 1,341 boundary-handoff evaluations died at or before ONE line. The complete reason set is `below-threshold` 845 · `team-assignee` 245 · `gate-not-green-at-head` 150 · `no-telemetry` 73 · `stale-telemetry` 20 · `dirty-tree` 10 · `no-cwd` 1 — and NOT ONE reason downstream of hooks/boundary-handoff.sh:317 ever appears (no `live-teammates`, no `log-head-lags`, no `latched`, no fire). So `[ "$green" = "$head" ] || abstain "gate-not-green-at-head"` has never once been passed. Both arms — the 73% fill arm and the 35% free-win arm — terminate in a single repo-wide predicate no session can influence: `.git/gate-green`, advanced only by the singleton postland verifier.

That predicate was already diagnosed and REMOVED from its sibling. scripts/wrap-ledger.sh:528-544 reads "GATE IS REPORTED, NEVER THE RUNG (2026-08-03) … the land path structurally cannot move it … RUNG=✅ was UNREACHABLE in this repo for five days," and cites CLAUDE.md's own sanction ("waiting on a trunk-wide stamp you do not control is not diligence, it is a hang"). The free-win arm landed in boundary-handoff the SAME DAY, into the un-fixed copy. So the shortest path to close the gap is one line at hooks/boundary-handoff.sh:317 — demote gate-green from a hard abstain to a reported field, exactly as wrap-ledger.sh already does — with the rationale, the precedent, and the policy citation already written down in the sibling file. That is a materially different and cheaper remedy than the claim's diagnosis implies (which points at a threshold, a role-file rename, and a config-dir key, none of which would move a single evaluation past line 317).

Evidence: INSTRUMENTS AND FIGURES (all MEASURED unless marked):

Event corpus — concatenated live + all 8 rotations: `{ cat ~/.claude/autonomy/idl.jsonl; for f in idl.jsonl.2*.gz; do gunzip -c "$f"; done; }` → 1,028,811 records (note: macOS `zcat` fails on .gz; `gunzip -c` used). jq tally by `.hook`: waiting-recycle 34,097 · boundary-handoff 1,341 · completion-assert 1,316 · operator-readout 1,289.
- boundary-handoff dispositions: 1,341 abstained, 0 fired. Full reason tally (collapsed): below-threshold 845, team-assignee 245, gate-not-green-at-head 150, no-telemetry 73, stale-telemetry 20, dirty-tree 10, no-cwd 1. Zero reasons downstream of :317.
- waiting-recycle dispositions: 34,069 abstained, 8 fired, 20 gc. Reasons: not-armed 26,295 (77.2%), disarmed 4,331 (12.7%), below-threshold-no-tell 873, dirty-tree-hold 716, recycle-machinery 90, rest team-assignee.
- All 8 "fired" records are `busy-nudge:dirty-tree-hold` (2026-08-09T23:54 → 2026-08-11T05:05). No recycle.
- Date range of the entire boundary-handoff record set: 2026-08-08 → 2026-08-11 (225/269/561/286 per day) — the IDL retention window, not a lifetime.

Fleet context distribution — jq over 1,551 transcript files (1,529 after dedup) under ~/.claude, ~/.claude-secondary, ~/.claude-tertiary, ~/.claude-quaternary `projects/`, `-type f -name '*.jsonl' -mtime -5`, taking per-file `max(input_tokens + cache_read_input_tokens + cache_creation_input_tokens)`:
  ≥730K (73% of 1M): 6 · 500–730K: 35 · 350–500K: 82 · 200–350K: ~466 · <200K: ~940. Top: 838,573 (.claude, claude-infrastructure c72f15e7); 780,382; 770,657; 767,339; 757,657; 750,639.
  INSTRUMENT NOTE (corrects the brief's stated gap): the transcript's bare `message.usage.input_tokens` is the UNCACHED slice only — max 18,918 fleet-wide, ~50× low. Resident context requires summing the two cache fields. And statusline.sh:130-136 shows `used_pct` is not derived by us at all: it is the harness's own `.context_window.used_percentage`, with `input_tokens: .context_window.total_input_tokens` and `window: .context_window.context_window_size`.
  Sampling trap: `~/.claude-next/projects -> /Users/chrisren/.claude/projects` (symlink; `ls -ld`). Plain `find` yields 0 for that root. Also `find -newermt '5 days ago'` is mis-parsed by this BSD find (10 hits vs 453 for `-mtime -5`).

Live telemetry (106 files in /tmp/cc-telemetry): window=1000000 on all but one (one claude-opus-4-8 at 200000); max observed used_pct = 68.

Code, cited:
- hooks/boundary-handoff.sh:99 `T="${CC_BOUNDARY_T:-73}"` (used_pct, a percentage — not a token count)
- hooks/boundary-handoff.sh:259 `T_FREEWIN="${CC_BOUNDARY_T_FREEWIN:-35}"`; :276-288 the arm order (forecast → size → free_win_now → abstain below-threshold)
- hooks/boundary-handoff.sh:316-317 `green="$(cat "$gitdir/gate-green" …)"` / `[ "$green" = "$head" ] || abstain "gate-not-green-at-head"`
- hooks/waiting-recycle.sh:205 `DESK_ROLE="${CC_WR_DESK_ROLE:-desk}"`; :220-229 set-but-empty must return 1; :500 role read; :533 `armed_by="desk-role"`; :535 `abstain "not-armed"`
- scripts/wrap-ledger.sh:528-544 "GATE IS REPORTED, NEVER THE RUNG (2026-08-03)" — gate-green already removed from the rung in the sibling file, with the measured five-day-unreachable-✅ rationale.

Deployment / staleness:
- `ls -la ~/.claude/hooks/{boundary-handoff,waiting-recycle}.sh` → symlinks into the checkout; checkout on `main` at 699bbb74; `git diff --stat origin/main` on both hooks + wrap-ledger.sh = empty. Bytes are HEAD.
- `git rev-parse --git-common-dir` → `.git`; `cat .git/gate-green` = 145fab7d26756ce6bb34ab356871d4b31f53947d (committed 2026-08-10 18:32, file mtime 20:08); `git rev-list --count 145fab7d..699bbb74` = 62.
- Free-win arm provenance: `git log -S'T_FREEWIN' -- hooks/boundary-handoff.sh` → ab6d3d1e5 2026-08-03 "feat(boundary-handoff): ✅-ledger free-win arm — a quiet session drains itself at 35%", contained in origin/main.
- `ls ~/.claude/cc-roles/` → `archive/` + `orchestrator`, size 0 bytes, Aug 9 16:10. No `desk`.
- `ls ~/.claude/state/waiting-recycle/` → exactly one `arm-` sentinel (Jul 26), one `disarm-`, one `cooldown-` (Jul 31); no `live-` sentinel, i.e. the exec path is SHADOW by design.
- Stop-hook registration identical in all four settings.json (jq over `.hooks.Stop[].hooks[].command`), all four written Aug 10 22:39.

UNKNOWN / not established: whether `.git/gate-green` has EVER equalled HEAD at a Stop within the IDL window (the absence of any downstream reason in 1,341 records says no, but that is 3.5 days of evidence, not all time); whether the prior investigator's 33,667/1,319 came from the live file alone or a partial rotation set; and the residual cause of the 369 free-win-eligible evaluations that returned false from `free_win_now` (the ✅-ledger predicate) rather than reaching :317.

**Instrument defect:** Four instrument defects found, three in the claim and one that would have caught me too.

(1) ALGEBRAIC RESTATEMENT: "the fleet never reaches 730,000 tokens" can only have been read off the `below-threshold:N<73` abstain records — which are the threshold test restated, over a population that structurally cannot contain a ≥73 reading (a session at ≥73 emits no such record). Independent measurement of the transcripts refutes it: 6 sessions crossed 730K in 5 days, max 838,573.

(2) SIBLING MECHANISM IGNORED: the cited T=73 was superseded in the same file by `T_FREEWIN=35` (hooks/boundary-handoff.sh:259) five days before the earliest record cited. 369 of 845 below-threshold records were ≥35.

(3) ROTATED-LOG UNDERCOUNT + "LIFETIME" OVERREACH: ~/.claude/autonomy/idl.jsonl has 8 `.gz` rotations. Concatenated totals are 1,341 / 34,097, not 1,319 / 33,667, and the entire boundary-handoff record set spans only 2026-08-08→08-11 — a 3.5-day retention window that cannot support "in the hook's entire lifetime". (macOS `zcat` returns 0 lines on a .gz; `gunzip -c` is required.)

(4) SYMLINKED CONFIG ROOT (a defect I hit myself and corrected): `~/.claude-next/projects` is a symlink to `~/.claude/projects`. Any four-config-dir census using plain `find` (no `-L`) silently returns ZERO transcripts for .claude-next — the primary account, 453 files in 5 days — while reporting a healthy total from the other three. Compounding trap on this box: `find -newermt '5 days ago'` is mis-parsed by BSD find (10 hits where `-mtime -5` gives 453).

(5) BRIEF-LEVEL INSTRUMENT CORRECTION (affects any re-derivation): the ground-truth brief states fill% = input_tokens/window with "the numerator durable in every transcript". The transcript's `message.usage.input_tokens` is the UNCACHED slice only — fleet max 18,918, roughly 50× low. Resident context = input_tokens + cache_read_input_tokens + cache_creation_input_tokens. Separately, `used_pct` is not computed by this repo at all: statusline.sh:134 copies the harness's own `.context_window.used_percentage`, so the "window lives only in ephemeral telemetry" gap is about *retrospective* re-derivation, not about what the live hooks read.

---

## Findings

### `[MEASURED][STRENGTH]` All four actuators are wired in all five config dirs, with matching events and paths — no 5-dir wiring drift on this axis.

- **Evidence:** Parsed hooks{} from ~/.claude, ~/.claude-next, ~/.claude-secondary, ~/.claude-tertiary, ~/.claude-quaternary settings.json. Every dir: PostToolUse[matcher=Bash] -> ~/.claude/hooks/waiting-recycle.sh; Stop[*] -> ~/.claude/hooks/session-continue.sh; Stop[*] -> ~/.claude/hooks/boundary-handoff.sh. Only drift: .claude-next sets timeout=30 on waiting-recycle, the other four leave it unset. handoff-fire.sh appears in settings.json only under permissions, not as a hook.
- **Source:** `python3 json parse of the five settings.json files`

### `[MEASURED][GAP]` waiting-recycle rides PostToolUse with matcher "Bash" ONLY, so a session doing Read/Edit/Agent/WebFetch work is never evaluated by the fleet's most capable context rail.

- **Evidence:** Same settings.json parse: matcher is the literal string "Bash" in all five dirs. The hook's own header (hooks/waiting-recycle.sh:546-547) acknowledges it "rides PostToolUse:Bash (~19x the Stop chain's rate)".
- **Source:** `settings.json parse + hooks/waiting-recycle.sh:546`

### `[MEASURED][STRENGTH]` No stale-deployed-bytes defect: every live path is a symlink into the checkout and is byte-identical to HEAD and to origin/main.

- **Evidence:** md5 live == worktree == HEAD for all four: waiting-recycle.sh 622b2cb5… (99,123 B), boundary-handoff.sh 30aa24ee… (29,050 B), session-continue.sh 09787348… (59,068 B), handoff-fire.sh a8ff7636… (598,677 B). `git diff --stat origin/main --` on the four files is empty. All 25 hooks/lib/*.sh are also symlinks into the checkout, including the ones session-continue sources (session-writes.sh, goal-state.sh).
- **Source:** `ls -la ~/.claude/hooks/*, md5 -q, git show HEAD:, git diff origin/main`

### `[MEASURED][GAP]` Over 3.05 days of fleet logs, waiting-recycle fired 8 times in 33,675 evaluations (0.024%) and every one of the 8 was an advisory nudge, not a recycle.

- **Evidence:** idl.jsonl + 8 rotated .gz archives, span 2026-08-08T05:09:40Z -> 2026-08-11T06:18:13Z: waiting-recycle abstained 33,667 / fired 8, all 8 with reason `busy-nudge:dirty-tree-hold` at used_pct 50-62. Zero `stage2-live` and zero `stage2-shadow` records.
- **Source:** `~/.claude/autonomy/idl.jsonl{,.*.gz}`

### `[MEASURED][GAP]` boundary-handoff — the only rail wired to every session — fired ZERO times in 1,319 evaluations over the same 3 days.

- **Evidence:** Same corpus: boundary-handoff abstained 1,319, fired 0. Reasons: 840 below-threshold, 242 team-assignee, 150 gate-not-green-at-head, 56 no-telemetry, 20 stale-telemetry, 10 dirty-tree, 1 no-cwd.
- **Source:** `~/.claude/autonomy/idl.jsonl{,.*.gz}`

### `[MEASURED][GAP]` The arm-by-default path that was shipped specifically to fix the not-armed problem is itself inert: it keys on a role file name the fleet does not use.

- **Evidence:** hooks/waiting-recycle.sh:205 `DESK_ROLE="${CC_WR_DESK_ROLE:-desk}"`; :216-227 is_monitoring_desk() returns 1 at :219 unless `$HOME/.claude/cc-roles/desk` exists. `ls ~/.claude/cc-roles/` shows only an EMPTY `orchestrator` file and archive/orchestrator.dead-pane-390. No `desk` file, none archived. CC_WR_DESK_ROLE is absent from all five settings.json. The header at :42-43 says this arm exists because "0/2419 prod fires decomposed as 1977 not-armed"; the live number is now 26,128 not-armed in 3 days.
- **Source:** `hooks/waiting-recycle.sh:205,216-227; ls ~/.claude/cc-roles/; rg CC_WR_DESK_ROLE over 5 settings.json`

### `[MEASURED][GAP]` The single deterministic auto-recycle arm points at a (config_dir, cwd) pair that no live session occupies, so the auto-exec is structurally unreachable today.

- **Evidence:** Only one live/arm marker pair exists: ~/.claude/state/waiting-recycle/{arm,live}-df1308af96473054, dated 2026-07-26. Reversing the key (hooks/waiting-recycle.sh:204 `CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"`, key=sha1("$CFG|$CWD")[1:16]) gives CFG=/Users/chrisren/.claude, CWD=claude-infrastructure. Live telemetry config_dir census: .claude-secondary 23, .claude-quaternary 11, .claude-next 7, .claude-tertiary 3, ~/.claude ZERO.
- **Source:** `~/.claude/state/waiting-recycle/ + shasum reverse + /tmp/cc-telemetry/*.json`

### `[MEASURED][GAP]` The one config dir that IS used in claude-infrastructure is explicitly disarmed, and the disarm was written 118 seconds after the last successful auto-recycle.

- **Evidence:** disarm-1c24a7da26668012 = sha1("/Users/chrisren/.claude-next|/Users/chrisren/Development/claude-infrastructure"), content `2026-07-31T17:58:44Z`. The last real `executed` recycle in recycle-events.jsonl is sid 89922bd6… at 2026-07-31T17:56:46Z. Nothing has re-armed it in 10 days; it accounts for 4,111 `disarmed` abstains in 3 days.
- **Source:** `~/.claude/state/waiting-recycle/disarm-1c24a7da26668012; ~/.claude/autonomy/recycle-events.jsonl`

### `[MEASURED][GAP]` The deterministic recycle has EXECUTED 3 times in the fleet's entire recorded history, and not once in 10 days.

- **Evidence:** recycle-events.jsonl spans 2026-07-30T02:44 -> 2026-08-11T05:43 with 2,545 rows, of which only 30 have a real UUID sid (2,515 are bats fixture sids s4/s5/fw1/s6e/t3c — the file is 99% test pollution). Of the 30 real rows: 20 nudged, 5 advised, 3 executed (2026-07-31T17:56, 2026-08-01T08:26, 2026-08-01T08:32), 1 behavioral, 1 forecast. Last 7 days: 10 real rows, 9 nudges + 1 forecast advisory, ZERO executed.
- **Source:** `~/.claude/autonomy/recycle-events.jsonl (uuid-filtered)`

### `[MEASURED][GAP]` Every recycle that actually happened in the last 2.4 days was chosen by the model, not fired by the system.

- **Evidence:** ~/.claude/logs/handoffs.jsonl (span 2026-08-08T20:58 -> 2026-08-11T05:42, n=1167) contains 8 rows of class `recycle-engaged` ("recycled in place; a real assistant turn within 0-15s"). Over the same window recycle-events.jsonl has 0 `executed`. So 8/8 recycles were agent-initiated handoff-fire --recycle calls.
- **Source:** `~/.claude/logs/handoffs.jsonl; ~/.claude/autonomy/recycle-events.jsonl`

### `[MEASURED][STRENGTH]` When an advisory does reach a session, the session acts — the defect is reach, not persuasion.

- **Evidence:** 3 of the 8 busy-nudges are followed by an agent recycle within minutes: nudge 2026-08-09T23:54:33 -> recycle-engaged 23:55:50; nudge 2026-08-11T01:16:21 -> recycle 01:19:30; nudge 2026-08-11T04:12:31 -> recycle 04:25:14.
- **Source:** `idl.jsonl fires cross-referenced with ~/.claude/logs/handoffs.jsonl`

### `[MEASURED][GAP]` boundary-handoff's fill threshold T=73 is functionally unreachable on this fleet's 1M windows, so 0/1319 is structural, not bad luck.

- **Evidence:** hooks/boundary-handoff.sh:99 `T="${CC_BOUNDARY_T:-73}"`. Live telemetry: 44 of 46 rows report window=1,000,000, so T=73 means 730,000 resident tokens. The largest input_tokens observed anywhere in live telemetry is 679,506 — and that session is alive. Fresh (<=180s) fills measured now: 15, 18, 18, 25, 29, 31, 39, 42, 55 — one of nine above the 35% free-win floor, none within 18 points of 73.
- **Source:** `hooks/boundary-handoff.sh:99; /tmp/cc-telemetry/*.json`

### `[MEASURED][GAP]` A stale shared gate-green marker silences boundary-handoff for every session in this repo AFTER it has already cleared the fill gate — 150 suppressed eligible evaluations in 3 days.

- **Evidence:** Order in code: below-threshold abstain at hooks/boundary-handoff.sh:286, gate check at :317 `[ "$green" = "$head" ] || abstain "gate-not-green-at-head"`. So all 150 records are past-threshold sessions. Measured now: .git/gate-green = 145fab7d (2026-08-10 18:32), HEAD = 699bbb74, 62 commits apart. gate-green lives in the shared common gitdir, so all 6 worktrees I sampled read the same stale 145fab7. The repo's own CLAUDE.md states only the background postland-verify stamp advances it.
- **Source:** `hooks/boundary-handoff.sh:286,317; git rev-list --count 145fab7d..HEAD; git worktree list + per-worktree gate-green read`

### `[MEASURED][GAP]` Both rails fail-OPEN when the fill signal is unknown — and the telemetry writer goes stale first on exactly the idle sessions the free-win policy targets.

- **Evidence:** boundary-handoff.sh:191 `[ -f "$tel" ] || abstain "no-telemetry"`; :198 abstain if age > AGE_MAX=180s; :199 `used="$(jq -r '.used_pct // 0' "$tel")"` — a present-but-fieldless file reads 0%. waiting-recycle abstains no-jq/:480, no-session-id/:513, no-cwd/:524 the same way. Measured freshness now: 46 telemetry files, only 9 within 180s, 23 within 1h, 14 older than 1h; 18 rows have a live pid. The writer is statusline.sh, which runs on TUI render, so an idle-at-prompt session stops refreshing and crosses AGE_MAX.
- **Source:** `hooks/boundary-handoff.sh:191,198,199; hooks/waiting-recycle.sh:480,513,524; stat on /tmp/cc-telemetry/*.json`

### `[MEASURED][GAP]` The 'window cannot be recorded' premise is stale on today's binary — the harness supplies it and the telemetry carries it.

- **Evidence:** statusline.sh:63-65 and :133-136 read `.context_window.context_window_size`, `.used_percentage`, `.total_input_tokens` directly from the harness payload; :356 falls back to 200000 only when the payload omits it. 44 of 46 live telemetry rows carry window=1000000, 1 carries 200000, 1 is null. The gap is telemetry FRESHNESS and COVERAGE (9 of 46 fresh), not window imputation.
- **Source:** `statusline.sh:63-65,133-136,356; /tmp/cc-telemetry/*.json`

### `[MEASURED][GAP]` Escalation is real in waiting-recycle and absent in boundary-handoff — the fleet-wide rail only ever repeats itself.

- **Evidence:** waiting-recycle: Stage-1 stamps cooldown + bumps cap + starts the grace clock (:1176-1180); Stage-2 is EXEMPT from both (:583-586 "a non-exempt Stage 2 would be permanently silenced after MAX ignored advisories"); a wedged desk pages out-of-band every ESCALATE_DEDUP_S=900s via wr_os_notify + wr_push_page and blocks (:1166-1178). boundary-handoff's only escalation is re-arming the SAME one-shot advisory on +10% fill, +10MB transcript, or a new HEAD sha (:335-355) — same message, same strength. Its own header calls it "a REFINEMENT, never the carrier" and notes it fires on Stop, so a session hung mid-turn never reaches it (:7-11).
- **Source:** `hooks/waiting-recycle.sh:583-586,1166-1180; hooks/boundary-handoff.sh:7-11,335-355`

### `[MEASURED][GAP]` Exactly one code path can auto-fire a recycle; every other rail is advisory, so the system is currently 100% 'proactive as an agent', 0% 'proactive as a system'.

- **Evidence:** hooks/waiting-recycle.sh:1112-1131 — `exec_ok=1` iff live_for($CWD) exists (idle) or additionally busyforce_for($CWD)/CC_WR_BUSY_FORCE=on (busy); then `"$HANDOFF_FIRE" --recycle --prompt-file "$pf"`. The default is SHADOW (:1140+): it composes the successor brief, logs shadow-would-fire, and does not exec. boundary-handoff and session-continue only emit decision:block text.
- **Source:** `hooks/waiting-recycle.sh:1109-1160`

### `[MEASURED][NEUTRAL]` session-continue is not a context-economy actuator at all — its 45 fires are ship/loose-end fires.

- **Evidence:** Over 3 days: 45 fired, 27 armed, 56 cleared. Fire reasons are exclusively `ship-floor` and `continue`; arm reasons `mechanical-dirty` / `cli-set`. No context or fill reason appears.
- **Source:** `~/.claude/autonomy/idl.jsonl{,.*.gz}`

### `[MEASURED][STRENGTH]` Despite the silence, there have been ZERO true context deaths in the last 8 days — 5 sessions / 8 events all-time, latest 2026-08-02.

- **Evidence:** Strict classifier over all four config dirs' transcripts (150 files containing the phrase): a true death = type=assistant, isApiErrorMessage=true, content text exactly 'Prompt is too long'. Result: 8 records, all assistant/assistant, in 5 sessions — 526aa752 (07-12), 8a34082e (07-17), 4fe8d91c (07-19), 076a1186 (07-26), c786f80f (08-02). My first pass reported 12 sessions / 26 events using an rg pattern; 7 of those files matched only the fleet's OWN PROSE about the phenomenon and agent grep commands containing the phrase — the same false-positive class as this fleet's 'pgrep -f matches agent briefs' memory. Note my strict 5/8 is below the ground truth's 7 sessions / 10 events; I could not reproduce the extra two with isApiErrorMessage and do not claim the ground truth is wrong.
- **Source:** `strict json classifier over ~/.claude*/projects/**/*.jsonl`

### `[MEASURED][GAP]` A live session carrying 314K resident tokens presents to every rail as 31% — below every threshold in the system.

- **Evidence:** Session d74ac142 (.claude-tertiary, claude-opus-5): last rail evaluation 2026-08-10T14:51:33Z read used_pct=31 and abstained `dirty-tree-hold`; its final usage record is input 2 + cache_creation 610 + cache_read 313,606 = 314,218 tokens. 314,218/1,000,000 = 31.4%, so the reading was arithmetically correct and operationally useless: T_IDLE=35, T_MIN=55, T=73 are all above it. (This session did NOT die — its 'Prompt is too long' hit was the agent's own grep command, verified at row 251.)
- **Source:** `idl.jsonl records for sid d74ac142; last usage block in ~/.claude-tertiary/projects/-Users-chrisren-Development-claude-infrastructure/d74ac142-*.jsonl`

## Unknowns

- Why the disarm marker for ~/.claude-next|claude-infrastructure was written at 2026-07-31T17:58:44Z, 118 seconds after the last successful auto-recycle — deliberate rollback after a bad fire, or collateral from a `waiting-recycle.sh clear`. The answer decides whether re-arming the exec is safe or is re-opening a known wound.
- Whether the 3 real `executed` recycles on 2026-07-31/08-01 behaved correctly (did the successor engage, did anything get stranded). recycle-events.jsonl records the verdict but not the outcome, and handoffs.jsonl does not reach back that far.
- My strict death classifier counts 5 sessions / 8 events all-time; the established ground truth says 7 sessions / 10 events. I could not reproduce the extra two — possibly a wider corpus (deleted/archived transcripts) or a different match rule. Unresolved, and I did not treat it as a refutation.
- Whether the recent zero-death record is attributable to agent discipline, to the fleet's shift onto 1M windows, or to a change in session-size distribution. 8 agent-initiated recycles in 2.4 days is real activity but I have no counterfactual.
- How many sessions are evaluated by NEITHER rail: waiting-recycle only sees PostToolUse:Bash and boundary-handoff only sees Stop. A session that neither runs Bash nor reaches Stop (hung mid-turn — boundary-handoff's own B-1 blind spot) is invisible to both, and I did not measure that population's size.
- Whether `.claude-tertiary`'s 1,000,000 window reading is trustworthy per-session, or whether the harness reports a configured window that the serving account may not honour. Every account showed live sessions above 200K surviving (max 679,506), so 1M is real for most — but I could not rule out a per-session entitlement mismatch.
