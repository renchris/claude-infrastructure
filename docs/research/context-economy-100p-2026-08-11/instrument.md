---
status: closed
created: 2026-08-11
owner: desk
---

# Can the system READ its own context fill at decision time

*Axis `instrument` of the context-economy 100th-percentile assessment `wf_5e9f820e-438`. Verdict: [`../context-economy-100p-2026-08-11.md`](../context-economy-100p-2026-08-11.md).*

**At 100th percentile:** `NO`

**Verdict.** No — at this instant only 11 of 20 live sessions (55%) can read a fill number their own hooks would trust, because the signal is written solely as a side-effect of TUI redraws into reboot-ephemeral /tmp, and the fleet's own freshness bound is 180s while the p90 row age is 2,550s.

**Load-bearing claim.** The fleet's headline context discipline runs on a signal that is absent or untrustworthy for 45% of live sessions at any instant — 3 of 20 have no row at all, and of the 17 that do, 6 are older than the 180-second bound the fleet's own hooks use to decide whether to believe them (p90 age 42.5 min, max 80 min) — and it degrades in exactly the wrong direction, because the row only refreshes on a TUI redraw, so a session inside one long heavy-burn turn is precisely the session whose number stops moving.

**Shortest fix.** Two edits, both in files that already hold the data. (1) In statusline.sh, next to the existing /tmp write (statusline.sh:129-138), also upsert `{sid, window, model, ts}` ONCE per session into a durable `$CLAUDE_CONFIG_DIR/autonomy/session-window.jsonl` — the window is fixed at launch, so one line per session survives the ~2-day /tmp wipe and gives cc-ctx-audit a real denominator index instead of 30 rows. (2) In bin/cc-context `resolve_me`/`emit_one`, add a fallback that computes fill live when the row is older than 180s: numerator = sum of `input_tokens + cache_read_input_tokens + cache_creation_input_tokens` from the LAST usage record in the session's own transcript (proven byte-exact against telemetry, updates several times per turn), denominator = the durable window from (1). That lifts decision-time readability from 55% to ~100% and makes it sub-turn rather than per-render, with no new producer and no dependence on the TUI. Separately and cheaply: point the bats suites at a fixtured `CC_RECYCLE_EVENTS`/`CC_TELEMETRY_DIR` (several suites already do; boundary-handoff.bats and the s*/b*/fw* emitters do not) so the durable store stops being 98.8% test residue, and change bin/cc-context:150 to render `?` instead of `0k` for a null window.

**Skeptic: REFUTED** (confidence high)

> The claim's load-bearing quantity is measured on the wrong population and is wrong by ~8x for the axis it was assigned. Measured on the fleet's OWN decision log (~/.claude/autonomy/idl.jsonl, one record per hook eval, 5h window 2026-08-11T01:34-06:27Z): boundary-handoff logged 246 real evals over 53 distinct real sessions; 187 of those reached the telemetry read, and only 10 (5.3% of evals, 3 of 53 sessions = 5.7%) were telemetry-blind — not 45%. waiting-recycle confirms independently at a DIFFERENT hook point (PostToolUse, not Stop): 96 fresh=1 vs 13 fresh=0 = 88% fresh at decision time. The blindness cost ZERO missed fires: the three blind sessions' own rows read used=47, 40, 68 against boundary-handoff's T=73 (hooks/boundary-handoff.sh:99). And 9 of the 10 stale events are ONE session (ee8e039d) — a count over a requeuing subject. The reason the instant-snapshot and the decision-log disagree is structural and is the OPPOSITE of the claim's mechanism: the row refreshes on a TUI redraw and the hooks fire at Stop/PostToolUse, so the same turn boundary drives both — the signal is freshest exactly when it is read.

WHAT SURVIVES, NARROWED: (1) The snapshot half is true and the claim UNDERSTATED it — of 18 live top-level claude sessions, 15 had a live-pid row and 11 of those 15 (73%) exceeded the 180s bound. (2) The wrong-direction case is real but is a long single OPERATION, not a "heavy-burn turn": correlating row age against each session's own transcript mtime, 7 of 15 track within seconds (stale => idle, benign), but ae6d0787 had a 4-second-old transcript and a 602-second-old row — live, actively writing, 10 minutes blind. A heavy-burn turn is many tool calls hence many renders (ee8e039d climbed 19->20->21% on consecutive fresh=1 evals 10-30s apart). (3) The genuine residual is a ~40-line WIRING gap, not fleet blindness: the fill decision path has no fallback — boundary-handoff.sh:196 and waiting-recycle.sh:621 both abstain on a stale row, and the one telemetry-independent axis is calibrated dormant by design (SIZE_MB=25 vs a measured live max of 22.4MB, waiting-recycle.sh:253-259) — while the substitute signal is ALREADY BUILT AND RUNNING in a sibling (scripts/lead-supervisor.sh:552-560 transcript_age() explicitly replaces telemetry age with transcript mtime, citing a measured 3.5-day-stale row on a 5-min-warm transcript) and simply is not wired into the two fill hooks. Abstain-on-stale is a fail-safe delay of one eval, not a corruption. That does not support an axis verdict of NO on its own.

The claim also presents as a discovery a property the repo documents verbatim and already compensates for: statusline.sh:76-79 states "a session inside ONE long operation, or genuinely hung, renders ZERO times and its telemetry goes arbitrarily stale WHILE ALIVE (observed: a live respawn at 78m stale)" and added the pid field precisely so age cannot be read as death.

MISSED BY THE CLAIM: scripts/lead-supervisor.sh:547 reap_clean() actively DELETES telemetry rows, so the "no row at all" bucket is partly sibling-daemon deletion, not only "never written" — evidence it is not a config-dir statusLine gap: pids 6687 (.claude-secondary) and 88196 (.claude-tertiary) are real interactive TUI sessions with no row while pid 46062 in the SAME .claude-secondary has one. Also, every live row reads window=1000000 (n=15); the only 200000 in the directory is a leftover bats fixture (sid dddd-eee, pid 6346, with 9999-888/aaaa-bbb), so any snapshot window census is fixture-contaminated.

Evidence: INSTRUMENTS AND MEASUREMENTS (all MEASURED unless labelled):

1. Live-session census (MEASURED, instrument: `ps -axo pid=,ppid=,etime=,comm=` filtered to comm matching ^claude, then top-level = ppid not itself a claude): 18 live sessions at 2026-08-10 23:28 PDT. /tmp/cc-telemetry holds 45 .json rows; only 16 carry a pid that `kill -0` answers (29 corpses).

2. Instant staleness (MEASURED, same instant, live-pid rows only, n=15 on the second pass): ages 7,13,24,34,194,295,398,477,579,602,932,1075,2992,3674,5267 s. 11 of 15 (73%) exceed the AGE_MAX=180 bound. This CONFIRMS and exceeds the claim's 6-of-17.

3. Decision-time blindness (MEASURED, instrument: ~/.claude/autonomy/idl.jsonl, the hooks' own per-eval disposition log, window 2026-08-11T01:34:06Z..06:27:01Z):
   - boundary-handoff reason census: 177 below-threshold, 39 team-assignee, 10 stale-telemetry, 8 gate-not-green-at-head, 17 no-telemetry.
   - The 17 no-telemetry records are 100% SYNTHETIC and excluded: every sid resolves to ~/.claude-quaternary/projects/-private-tmp-...-2a3e1957-...-scratchpad-probe{,2,3}/<sid>.jsonl — 19-20 line headless `claude -p "Reply with exactly: ok"` probes a sibling investigator was firing DURING this measurement (count grew from 15 to 17 between two reads). Headless sessions render no TUI so can never have a row.
   - Real telemetry-reaching evals = 177 + 10 = 187. Blind = 10 => 5.3%.
   - Per-session: 70 distinct sids logged, 20 ever-blind, of which 17 are the probes => 3 of 53 real sids = 5.7%.
   - Requeuing subject: the 10 stale events are 3 sids; ee8e039d accounts for 9 (05:53:59 through 06:05:07, ages 436s..1104s).
4. Independent second hook (MEASURED, same log): waiting-recycle embeds a `fresh=` token in its reason string. grep -o 'fresh=[01]' => fresh=1: 96, fresh=0: 13 => 88% fresh at decision time. This is a PostToolUse hook, not a Stop hook, so it is not fresh-by-construction in the same way boundary-handoff is.

5. Cost of the blindness = ZERO missed fires (MEASURED): the three real blind sids' own current rows read used_pct 47 (ee8e039d), 40 (1080a160), 68 (e5d3628d) against boundary-handoff T=73 (hooks/boundary-handoff.sh:99). None would have fired. e5d3628d at 68 is the near-miss.

6. Direction test (MEASURED, row ts vs the session's own transcript mtime, n=15): pairs (rowage,txage) = (7,7) (13,14) (24,25) (34,34) (194,195) (295,293) (398,391) (477,333) (579,385) (602,4) (932,744) (1075,64265) (2992,777) (3674,2952) (5267,2995). Seven track within seconds => stale means idle. ae6d0787 = (602,4) is the clean confirmation of the claim's mechanism: transcript written 4s ago, row 602s old. ee8e039d showed used climbing 19->20->21 across consecutive fresh=1 PostToolUse evals 10-30s apart, i.e. a busy multi-tool turn keeps the row fresh.

7. Code citations (repo-relative, /Users/chrisren/Development/claude-infrastructure):
   - statusline.sh:76-79 — the sole writer; documents the exact staleness mechanism the claim presents as new, and statusline.sh:117-124 adds the `pid` field because "AGE alone can never distinguish a stall from a healthy long turn".
   - hooks/boundary-handoff.sh:99 (T=73), :100 (AGE_MAX=180), :196-201 (abstain "stale-telemetry:${age}s" / "no-telemetry").
   - hooks/waiting-recycle.sh:197 (AGE_MAX=180), :616-627 (fresh=0/used=0 on a stale row), :662-666 (size axis deliberately NOT telemetry-gated), :253-259 (size defaults DORMANT against the measured fleet — SIZE_MB=25 vs live max 22.4MB).
   - scripts/lead-supervisor.sh:552-560 transcript_age() — the already-built substitute signal, citing "measured 2026-07-19: a live session at 3.5-DAY-stale telemetry with a 5-min-warm transcript".
   - scripts/lead-supervisor.sh:547 reap_clean() — `rm -f "$TEL_DIR/$1.json"`, i.e. rows are actively deleted by a sibling daemon.

8. Window census (MEASURED): all 15 live rows report window=1000000. The only 200000 value in /tmp/cc-telemetry belongs to synthetic fixture rows sid 9999-888 / aaaa-bbb / dddd-eee, all pid 6346 — bats fixtures written into the REAL directory.

UNKNOWN (not resolved): why pids 6687 and 88196 — real interactive TUI sessions, 11h56m and 24h uptime — have no row, when pid 46062 in the same CLAUDE_CONFIG_DIR does. reap_clean() deletion is the leading candidate but I did not find a reap record for them in the IDL window available.

SCOPE CAVEAT: the IDL window is ~5h of one day. boundary-handoff is a Stop hook and is therefore fresh partly by construction; that is why I anchored the independent 88% figure on waiting-recycle, which fires at PostToolUse.

**Instrument defect:** Population defect: the claim measures row age across LIVE SESSIONS AT A WALL-CLOCK INSTANT, but the axis it was assigned is "can the system read its fill AT DECISION TIME". Those populations differ systematically because the writer (a TUI redraw) and the reader (a Stop / PostToolUse hook) are driven by the SAME turn boundary — so the instant-snapshot is dominated by sessions that are idle or mid-long-operation, i.e. precisely the sessions not currently making a decision, while every session that IS making one has just rendered. The fleet keeps a per-eval decision log (~/.claude/autonomy/idl.jsonl) that answers the assigned question directly and was not consulted; it reads 5.3% blind, not 45%. Secondary defects: (a) the 10 stale events are a count over a REQUEUING SUBJECT — 9 of them are one session, so "sessions affected" is 3 of 53, not a fleet property; (b) any IDL-based no-telemetry count in this window is contaminated by the investigation's OWN headless `claude -p` probe sessions (17 records, all distinct sids, all under .../scratchpad/probe{,2,3}), which structurally can never have a row; (c) any /tmp snapshot is contaminated by leftover bats fixture rows (pid 6346, including the sole window=200000 value) and by 29 dead-pid corpses; (d) the claim treats "no row" as a write-side property while scripts/lead-supervisor.sh:547 actively DELETES rows; (e) the gap is largely closed by a sibling mechanism the claim did not check — lead-supervisor.sh:552-560 transcript_age() already substitutes transcript mtime for telemetry age on the same measured evidence.

---

## Findings

### `[MEASURED][GAP]` At 2026-08-10 23:2x local, 20 live `claude` processes exist; 17 (85%) have a pid-matched telemetry row; 3 (pids 6687, 88196, 46828) have none at all.

- **Evidence:** `ps -axo pid=,comm=` filtered to comm basename ^claude → 20 pids. Per-pid scan of /tmp/cc-telemetry/*.json matching `.pid` → 17 hits, 3 NO-ROW. Script /tmp/fresh.sh.
- **Source:** `live process table + /tmp/cc-telemetry (instrument: /tmp/fresh.sh)`

### `[MEASURED][GAP]` Only 11 of 20 live sessions (55%) have a row that is BOTH ≤180s old and carries a non-null used_pct. Median row age 133s, p90 2,550s (42.5 min), max 4,825s (80 min).

- **Evidence:** Same scan: fresh<=180s_AND_usable=11; ages sorted → median 133, p90 2550, max 4825.
- **Source:** `/tmp/fresh.sh over live pids`

### `[MEASURED][NEUTRAL]` 180s is not my threshold — it is the fleet's own. Both deterministic rails hard-abstain above it.

- **Evidence:** hooks/boundary-handoff.sh:100 `AGE_MAX=180  # abstain if telemetry older than this (can't trust stale)` and :198 `[ "$age" -le "$AGE_MAX" ] || abstain "stale-telemetry:${age}s"`; hooks/waiting-recycle.sh:197 `AGE_MAX="${CC_WR_AGE_MAX:-180}"`.
- **Source:** `repo file:line`

### `[MEASURED][GAP]` The row is written ONLY as a side-effect of a statusline render, so a session inside one long turn — exactly the heavy-build regime the ~75% drain rule targets — goes arbitrarily stale WHILE ALIVE. The code says so itself.

- **Evidence:** statusline.sh:76-80: "The statusline renders on UI updates… a session inside ONE long operation, or genuinely hung, renders ZERO times and its telemetry goes arbitrarily stale WHILE ALIVE (observed: a live respawn at 78m stale)." Live confirmation: 4 of 17 rows for ALIVE pids are 36m/42m/48m/80m old.
- **Source:** `statusline.sh:71-140 + live row ages`

### `[MEASURED][GAP]` When the signal is missing the rails fail toward NEVER RECYCLING, not toward caution. waiting-recycle logs `used=0,fresh=0` and then abstains as below-threshold.

- **Evidence:** IDL ($HOME/.claude/autonomy/idl.jsonl, current rotation 2026-08-11T01:28→06:20Z, 48,884 lines): waiting-recycle 4,690 abstains / 2 fires; of the 107 records that reached the fill test, 12 (11.2%) carry `fresh=0` and all of those carry `used=0` — e.g. `below-threshold-no-tell:used=0,fresh=0,rot=0,floor=25`. boundary-handoff: 230 evaluations, 0 fires, 10 `stale-telemetry` abstains (4.3%).
- **Source:** `idl.jsonl via jq (instrument: /tmp/idlagg.sh)`

### `[MEASURED][STRENGTH]` CHALLENGE TO GROUND TRUTH — the live decision-time read does NOT need the window at all. The harness hands the statusline a precomputed `context_window.used_percentage`; the telemetry row copies it verbatim. So the live failure mode is FRESHNESS, not the missing denominator.

- **Evidence:** statusline.sh:63-64 reads `.context_window.used_percentage` and :134 writes it as `used_pct`; statusline.sh:340 `Context % — EXACT /context parity when the payload exposes used_percentage (CC ≥2.1.207)`. Live rows all carry used_pct independent of any window arithmetic.
- **Source:** `statusline.sh:56-140, 337-360`

### `[MEASURED][GAP]` CHALLENGE TO GROUND TRUTH — the 'claude-opus-4-8 ran at BOTH 1,000,000 and 200,000' evidence does not exist in today's live telemetry as real data. All 42 uuid-named (real) rows are window=1,000,000. The only 200,000 and null windows are 3 bats fixture files.

- **Evidence:** Per-file scan of /tmp/cc-telemetry/*.json by filename shape: uuid 1000000 claude-opus-5 ×34, uuid 1000000 claude-fable-5 ×8, fixture 1000000/200000/null claude-opus-4-8 ×3. The three fixtures are 9999-8888-7777.json, aaaa-bbbb-cccc.json, dddd-eeee-ffff.json — cwd `/Users/x/p`, pid 6346, mtime Aug 10 17:24. I cannot prove what the 2026-07-29 measurement saw; I can prove a re-derivation TODAY would ingest these three.
- **Source:** `/tmp/cc-telemetry file census + `cat 9999-8888-7777.json``

### `[MEASURED][GAP]` The durable store built specifically to preserve the denominator is 98.8% test residue. Of 2,545 records in recycle-events.jsonl, only 30 (1.2%) come from a real session; 2,515 carry bats fixture sids (s4, b10, s5, s1, b3, b1, b9, b8, b11, s3, fw1) and every one of them has window:null.

- **Evidence:** `jq -r .sid $HOME/.claude/autonomy/recycle-events.jsonl | sort | uniq -c` → s4:352, b10:352, s5:350, s1:182, b3/b1:177, b9/b8/b11:176, s3:175, fw1:105…; uuid-shaped sids = 30 of 2,545. Window present:1000000 = 30, NULL = 2,515 — the null population IS the test population.
- **Source:** `$HOME/.claude/autonomy/recycle-events.jsonl`

### `[MEASURED][GAP]` Across 12 days (2026-07-30 → 2026-08-11) the durable store records exactly 3 EXECUTED recycles fleet-wide; the other 27 real records are 20 nudges + 7 advisories. The IDL's fill-drop channel has 0 records in the current rotation.

- **Evidence:** `jq 'select(.window!=null)|.verdict+"|"+.trigger+"|"+.mode'` → 20 nudged|busy-nudge|idle, 5 advised|threshold|idle, 3 executed|threshold|idle, 1 advised|behavioral|idle, 1 advised|forecast|boundary. `jq 'select(.reason=="fill-drop")' idl.jsonl | wc -l` → 0.
- **Source:** `recycle-events.jsonl + idl.jsonl`

### `[MEASURED][GAP]` cc-context renders a BLANK for unknown fill (correct) but a WRONG NUMBER for unknown window.

- **Evidence:** bin/cc-context:148 `((.used_pct // "?")|tostring) + "%"` → renders `?%` (verified live: 4 rows rendered `?%`). bin/cc-context:150 `(((.window // 0) / 1000 | floor | tostring) + "k")` → a null window renders `0k`, a fabricated value, not a blank.
- **Source:** `bin/cc-context:144-160 + live `cc-context` table output`

### `[MEASURED][GAP]` The window is recoverable NOWHERE durable today: the transcript JSONL does not carry it, and none of the 14 SessionStart hooks captures it.

- **Evidence:** `grep -c context_window` on a live 22MB transcript → 0 (the only repo-wide `context_window_size` hits are prose in agent transcripts/memory files). `jq .hooks.SessionStart[].hooks[].command settings.json` → 14 hooks (session-start, session-register, live-session-registry, dod-persist, …); `rg -l context_window hooks/ scripts/ bin/` → only scripts/telemetry-e2e.sh. Confirms the ground-truth durability claim.
- **Source:** `live transcript + ~/.claude-next/settings.json + repo grep`

### `[MEASURED][GAP]` /tmp is wiped roughly every 2 days: 7 reboots in the last 14 days. Current uptime 1 day 18:57.

- **Evidence:** `uptime` → up 1 day, 18:57, load 23.56. `last reboot` → Aug 9 04:18, Aug 9 03:39, Aug 5 00:19, Jul 31 18:13, Jul 31 11:46, Jul 30 02:18, Jul 27 19:02.
- **Source:** `uptime / last reboot`

### `[MEASURED][STRENGTH]` The NUMERATOR is already durable at sub-turn granularity and matches the telemetry EXACTLY — so a freshness fix needs no new producer.

- **Evidence:** Session 0db6fcda: telemetry `input_tokens:314316`; transcript last `input_tokens + cache_read_input_tokens + cache_creation_input_tokens` = 314,316 — byte-exact. 165 usage records in that one file, three of them within 9 seconds, i.e. it updates mid-turn while the statusline does not.
- **Source:** `/tmp/cc-telemetry/0db6fcda*.json vs .../0db6fcda-…jsonl`

### `[MEASURED][STRENGTH]` This is NOT the stale-deployed-bytes defect. The producer and all readers are running HEAD.

- **Evidence:** `diff <(git show origin/main:statusline.sh) ~/.claude/statusline.sh` → IDENTICAL. cc-context, waiting-recycle.sh, boundary-handoff.sh, lib/context-econ.sh are all symlinks into the checkout. statusLine configured in all four config dirs (`{"type":"command","command":"~/.claude/statusline.sh"}`).
- **Source:** `diff + ls -la ~/.claude/... + jq over 4 settings.json`

### `[MEASURED][STRENGTH]` Sessions do reach for the signal — 319 of 1,313 transcripts in the last 7 days (24%) invoke cc-context/cc-ctx-audit — so the read side is exercised, not dead code.

- **Evidence:** find */projects -name '*.jsonl' -mtime -7 + grep: next 0/0 (config dir has no recent project transcripts under that path), secondary 62/472, tertiary 59/324, quaternary 198/517. Total 319/1,313.
- **Source:** `transcript grep across 4 config dirs (instrument: /tmp/ccuse2.sh)`

## Unknowns

- Whether the established 'claude-opus-4-8 ran at both 1,000,000 and 200,000' finding (2026-07-29) rested on real rows since reaped, or on the same bats fixture files that sit in /tmp/cc-telemetry today. I can prove the fixtures are there now and that every real row is 1,000,000; I cannot reconstruct the July population.
- Which suite writes 9999-8888-7777.json / aaaa-bbbb-cccc.json / dddd-eeee-ffff.json into the LIVE /tmp/cc-telemetry (mtime Aug 10 17:24). A repo grep for those literals found only unrelated compound UUIDs, so the writer builds the name from a variable.
- Why 3 live sessions have no telemetry row at all. pid 88196 (23h52m, no argv prompt) and pid 6687 (11h45m, fired with a brief) are both `.claude-220` TUI sessions that should render a statusline; `lsof` returned no transcript path for either under this uid, so I could not resolve their session ids to confirm whether a row exists under a different pid.
- Whether the statusline reliably renders BEFORE the Stop hook fires at a turn boundary. boundary-handoff's 10 `stale-telemetry` abstains out of 230 (4.3%) suggest it usually does, but 230 evaluations in one ~5h IDL rotation is a thin sample and most abstains exit on earlier gates before reaching the telemetry read.
- The real denominator of the 55% figure over time — this is one instant on one machine at load 23.56. The direction is clear (staleness tracks turn length) but I did not sample the freshness distribution repeatedly across a day.
