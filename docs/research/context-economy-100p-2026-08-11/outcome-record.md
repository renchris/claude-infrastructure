---
status: closed
created: 2026-08-11
owner: desk
---

# What actually happens at end-of-session, measured across the fleet

*Axis `outcome-record` of the context-economy 100th-percentile assessment `wf_5e9f820e-438`. Verdict: [`../context-economy-100p-2026-08-11.md`](../context-economy-100p-2026-08-11.md).*

**At 100th percentile:** `NO`

**Verdict.** No — the fleet is cool and deaths are rare (5 in 30d, 0.2%), but only 10.3% of session endings are a context-driven succession act while 35.1% just stop mid-context, and the two deterministic rails that were supposed to force the decision fired 5 times in 19,742 evaluations (0.025%) because 65–90% of their evaluations abstain on `not-armed`, so today's good outcome is model discipline, not mechanism.

**Load-bearing claim.** Across 2,904 ended sessions in 30 days over all four accounts, the fleet reaches the right context outcome by model discipline and pays for it at the top: recycle rate rises 0.3% → 35.8% as peak occupancy climbs 100K → 800K, deaths are 5 (0.2%) and 4 of them ≥800K, but the deterministic rails that are supposed to make the decision unmissable fired 5 times in 19,742 evaluations because 65–90% of evaluations abstain on `not-armed`, and the 41 sessions that announced a recycle and never fired one (21 with no successor at all, the worst at 854K) are exactly what a rail exists to prevent.

**Shortest fix.** Make the fire atomic and the rail unconditional, in that order. (1) ATOMICITY — the measured failure is never "the agent didn't know", it is "the agent wrote the brief and the fire never ran": three of the top five cases end on a Write/heredoc of the successor payload with no handoff-fire invocation. Change `handoff-fire.sh --recycle` so brief-capture and fire are ONE tool call (accept the brief on stdin / `--brief-from-stdin`, or have the agent fire first with a pointer and let the successor read a file the fire itself wrote), so the sequence cannot die in the gap it currently dies in. (2) ARMING — 91% of waiting-recycle's abstains are `not-armed`/`disarmed`, so the tiering, the forecast and the pause-point nudge are all unreachable for the ~15 non-desk sessions; flip arm-by-default from "session holding the DESK role" (hooks/waiting-recycle.sh:402) to every session, keeping `disarm` as the explicit opt-out that 1,341 evaluations already use. (3) Free correction while there: stop the test suite writing 2,515 window:null rows into the live ~/.claude/autonomy/recycle-events.jsonl (point tests at CC_WR_STATE_DIR/a tmp store), so the durable window index cc-ctx-audit reads can actually accumulate, and fix bin/cc-ctx-audit:12's header to say occupancy = input + cache_creation + cache_read, matching its own line 231 — that stale sentence is what put a wrong numerator into this investigation's brief.

**Skeptic: REFUTED** (confidence high)

> The claim's OUTCOME half reproduces exactly and survives; its MECHANISM half — the load-bearing "today's good outcome is model discipline, not mechanism" — is refuted on three independent grounds, and the corrected finding is sharper than the original.

WHAT SURVIVES (independently reproduced, all four config roots, 30 days, 6,932 transcripts / 6,720 with ≥1 assistant message):
• Deaths = 5 sessions / 8 events. Peaks 444,605 · 968,390 · 970,045 · 976,563 · 976,626. Four of five are ≥800K. Matches the claim to the unit.
• The announce-then-never-fire population is real and its worst case is 854,395 tokens — the claim's "854K", matched to the digit by an independently written detector.
• Recycle rate does rise with peak occupancy, and this is NOT an algebraic restatement of session length: holding turn count fixed at 100–200 assistant messages, the self-recycle rate still climbs 0.3% (<200K, n=392) → 1.7% (200–400K, n=644) → 30.0% (400–600K, n=10). The correlation survives the length control.

WHAT IS REFUTED:
1. THE MECHANISM WINDOW CONTAINS ZERO DEATHS. The rails' only evidence store — ~/.claude/autonomy/idl.jsonl plus its 8 gz rotations — retains 2026-08-08T10:11Z → 2026-08-11T06:31Z, ≈3.1 days, structurally bounded by ROTATE_KEEP=8 (scripts/rotate-autonomy-logs.sh:76). All five deaths occurred 2026-07-12 → 2026-08-02. The claim pairs a 30-day outcome statistic with a 3-day mechanism statistic that overlaps none of the failing cases. The rails cannot be convicted of failing to prevent deaths against which they were never measured.
2. THE FIRE ARITHMETIC AND THE `not-armed` ATTRIBUTION ARE BOTH WRONG. Over the fully-retained window: waiting-recycle 34,192 evaluations / 8 fires; boundary-handoff 1,344 evaluations / 0 fires — 35,536 total, not 19,742. And boundary-handoff has ZERO `not-armed` abstains: it has no arm at all. Its abstains are `below-threshold:N<73` (majority), `gate-not-green-at-head` (150), `no-telemetry` (73), `team-assignee` (58). It never fired because the maximum context fill it ever observed at a Stop was 71, below its threshold T=73 (hooks/boundary-handoff.sh:99) — 0 of 1,344 evaluations reached the fire condition across 296 distinct sessions. That is a rail correctly quiet over an empty population, not a rail defeated by an arming gap.
3. THE `not-armed` ABSTAIN IS waiting-recycle's DESIGNED SCOPE, AND A SIBLING MECHANISM ALREADY ADJUDICATES IT. waiting-recycle is a monitoring-desk hook; hooks/waiting-recycle.sh:43 states the arm gate exists so "A builder (no arm sentinel, not the desk role) is still never touched," and scripts/desk-recycle-invariant.sh:23 says verbatim "`not-armed` genuinely is healthy-dormant — a builder must never self-recycle." That invariant is deployed and logging (273 records in the window), and every one reads `no-desk` — there is no monitoring desk running, so the rail's true population is ~zero and 26,332 builder abstains in its denominator is a denominator defect. The historical stranded-arm failure the claim is echoing was already diagnosed and closed by scripts/desk-arm-live.sh (config-root discovery, :17-19, :85). Both rails are live-deployed and byte-identical to origin/main — no stale-bytes defect.
4. THE REPO ALREADY STATES THE ZERO-FIRE FACT AND ADJUDICATES IT OPPOSITELY, UNADDRESSED. hooks/boundary-handoff.sh:373-374: "Measured before this landed: 2,173 evaluations, 2,173 abstains, ZERO fires in the hook's entire lifetime"; :90-92: "every reason is a HEALTHY condition-not-met." The claim presents this as discovery and flips the verdict without engaging the reasoning.

THE CORRECTED, STRONGER FINDING — and the real gap:
The hazard is not fleet-wide and is not "rare." It is a CLIFF, and past it survival is zero: of 18 sessions reaching ≥800K peak occupancy, 4 died (22.2%); of the 4 reaching ≥950K, 4 died — 100%, no survivors. "Deaths are 0.2%" averages a certainty over a population that never went near it.
The mechanism gap is therefore not arming and not discipline: it is that both rails key on fill% = tokens ÷ window, and the window is the one value this fleet cannot durably read, while the hazard is an ABSOLUTE token count that is durable in every transcript's own `usage` block and available to the Stop hook with no /tmp telemetry at all. Measurably, the 73%-of-unknown-window arm was never once in range in 1,344 evaluations; an absolute-token arm would have been in range for 4 of the 5 deaths.
SHORTEST PATH: add an absolute-token arm to boundary-handoff.sh — fire on cumulative input+cache_read+cache_creation ≥ ~700K regardless of window, telemetry, or arm sentinel — and keep the 73% arm as the secondary. It needs no arm, no window value, and no desk. Second, the announce-then-never-fire population (27 by my detector, 41 by theirs; worst at 854,395, sitting ~100K below the certain-death band) is the one place their claim correctly identifies an unguarded seam: an announced-but-unfired recycle is a state a Stop hook can see and latch.
AXIS VERDICT: their NO stands, but not for their reason. It is NO because the rails are calibrated on a denominator the fleet cannot measure while the actual failure mode is an absolute count it records perfectly — not because the rails are unarmed or because discipline is doing the work unaided.

Evidence: POPULATION (MEASURED — python scan of every *.jsonl mtime<30d under the four config roots; ~/.claude-next/projects is a SYMLINK to ~/.claude/projects, so `find` without -L reports 0 files there — I followed it):
  .claude 1,648 · .claude-secondary 1,758 · .claude-tertiary 2,148 · .claude-quaternary 1,386 = 6,932 files; 6,720 with ≥1 assistant message. Per-session facts in /tmp/sess2.tsv.

DEATHS (MEASURED — exact normalised equality on assistant text, the same detector docs/plans/CONTEXT_ECONOMY_V2.md:195 names; a naive `rg 'Prompt is too long'` returns 152 files, a ~30× overcount false-positived by file CONTENT being written, e.g. line 204 of ~/.claude/projects/-Users-chrisren-Development--worktrees-wt-2d687628ce46/47ad76f7-5203-4ad0-b5b3-73b23dd6dbe0.jsonl is a tool_result echoing GROUND_UP_REBUILD_MAP.md):
  5 files / 8 events, one in EACH of the four roots (a 3-root sample missing ~/.claude would have found 4).
  peaks 444,605 · 968,390 · 970,045 · 976,563 · 976,626; dates 2026-07-12T08:28Z, 2026-07-17T07:04Z, 2026-07-19T03:57Z, 2026-07-24T22:18Z, 2026-08-02T06:42Z.

CLIFF (MEASURED, derived from the same scan): peak ≥800K n=18, deaths 4 = 22.2%. peak ≥950K n=4, deaths 4 = 100.0%. Bucket census: 0K n=2196 · 100K n=2725 · 200K n=1103 · 300K n=325 · 400K n=155 · 500K n=97 · 600K n=57 · 700K n=44 · 800K n=12 · 900K n=6; max peak 976,626.

RECYCLE ACTS (MEASURED, `handoff-fire … --recycle` in a tool_use command): 179 sessions self-recycled (2.7%); 874 self-closed; 806 fired a peer only. Rate by peak bucket: 0.1% / 0.9% / 2.1% / 6.5% / 15.5% / 35.1% / 35.1% / 47.7% / 50.0% / 50.0%. Length control at 100–200 turns: 0.3% (<200K) → 1.7% (200–400K) → 30.0% (400–600K).

RAILS (MEASURED — ~/.claude/autonomy/idl.jsonl + 8 rotations decompressed with `gzip -dc`; NOTE `zcat` on this macOS returns 1 line vs gzip -dc's 118,536 on the same archive, the fleet's own known instrument trap):
  window 2026-08-08T10:11:50Z → 2026-08-11T06:31:52Z (≈3.1 days), 1,029,466 records.
  waiting-recycle: 34,192 evaluations, 445 distinct sids. abstained 34,164 · gc 20 · fired 8. All 8 fires are `busy-nudge:dirty-tree-hold` (Stage-1 advisory on a busy desk); ZERO `stage2-live`, ZERO `stage2-shadow`, ZERO plain `waiting-recycle` fires. Abstain reasons: not-armed 26,332 (77.0%, 326 sids) · disarmed 4,389 (12.8%, 62 sids) · dirty-tree-hold 716 · the rest below-threshold / team-assignee / recycle-machinery.
  boundary-handoff: 1,344 evaluations, 296 distinct sids, 1,344 abstains, 0 fires, 0 escalations. `not-armed`/`disarmed` count = 0. gate-not-green-at-head 150 · no-telemetry 73 · team-assignee 58 · remainder `below-threshold:N<73`. Max N ever observed = 71; evaluations with N≥73 = 0.
  desk-recycle-invariant: 273 records, all `no-desk` ("no live desk process resolves from ~/.claude/cc-roles/desk").

DEPLOYMENT (MEASURED, shasum): ~/.claude/hooks/{waiting-recycle,boundary-handoff,session-continue}.sh are symlinks into the checkout and are byte-identical across deployed == worktree == origin/main (9a356a62… / 2cf61d47… / bb338a68…). No stale-deployed-bytes defect on either rail.

REPO CITATIONS: hooks/waiting-recycle.sh:43 (builder never touched by design), :99–:1189 (fire paths); hooks/boundary-handoff.sh:99 (T=73), :90-92 (abstains are healthy condition-not-met), :317 (gate-not-green-at-head), :373-374 (2,173 evaluations / 2,173 abstains / zero fires in lifetime, already in-tree); scripts/desk-recycle-invariant.sh:23, :42, :279-284 (not-armed = healthy-dormant for a builder; PAGE only when the DESK cwd has no arm); scripts/desk-arm-live.sh:17-19, :85 (the stranded-arm root cause and its discovery-based fix); scripts/rotate-autonomy-logs.sh:76 (ROTATE_KEEP=8).

UNKNOWN (stated, not resolved): the claim's "2,904 ended sessions", "10.3% context-driven succession", "35.1% stop mid-context" and "19,742 evaluations" use filters I could not reconstruct; 2,904 is 42% of my 6,932 and 19,742 is 56% of my 35,536. Their 0.2% death rate uses the 2,904 denominator; over all 30d transcripts it is 5/6,932 = 0.07%.

**Instrument defect:** The rail-effectiveness figure is computed from an instrument with a ~3-day retention (idl.jsonl, ROTATE_KEEP=8, size-triggered) and then juxtaposed with a 30-day outcome population, so the mechanism denominator excludes every failing case — all 5 deaths predate the earliest retained IDL record by 6 to 30 days. Two further instrument traps sit on the same path: `zcat` silently returns 1 line where `gzip -dc` returns 118,536 on the identical archive (so an archive-inclusive count can collapse to live-file-only without erroring), and `find ~/.claude-next/projects` without -L returns 0 files because that path is a symlink to ~/.claude/projects (so a four-root sweep can silently become three). Separately, `not-armed` is used as a failure reason across both rails when it is (a) the documented healthy-dormant scope gate of one rail whose population — monitoring desks — is currently empty, and (b) entirely absent from the other rail, whose real quiet reason is that fill never once reached its 73 threshold in 1,344 evaluations.

---

## Findings

### `[MEASURED][NEUTRAL]` SAMPLE: 6,942 transcripts (6.34 GB) modified in the last 30 days across ALL FOUR config dirs (.claude-next 1,644 · .claude-secondary 1,774 · .claude-tertiary 2,161 · .claude-quaternary 1,363). 3,558 of these are `agent-*.jsonl` teammate/subagent files (100% sidechain-only, no operator turn) and are excluded from ending analysis; the real-session population is 3,037, of which 2,904 had ended (last event >6h old) and 133 may still be live.

- **Evidence:** find -L over the four dirs + /tmp/.../scratchpad/scan3.py; per-account counts and the agent-vs-session split verified by basename prefix and by lastassist_line==-1 in 3,238/3,238 agent files vs 12/3,037 session files.
- **Source:** `scratchpad/files30.txt, scratchpad/scan3.py, scratchpad/s3_30.jsonl`

### `[MEASURED][GAP]` ENDING DISTRIBUTION (n=2,904 ended sessions, 30d): recycle fired 4.5% · handoff fired 5.8% · self-close fired 25.7% · closed with a ledger-rung message but no succession act 27.1% · assistant's last message with no rung and no act 35.1% · no close signal at all 1.7% · died on 'Prompt is too long' 0.2%. So 36.0% ended on an explicit machine act, but only 10.3% ended on a CONTEXT-driven act — `handoff-fire.sh self-close --terminal…` is an assignee finishing its task and closing its pane, not a recycle.

- **Evidence:** Classification keys on tool_use Bash commands parsed out of the last 60 transcript lines (`handoff-fire` ± `--recycle`, `self-close`), not on substring presence — a raw grep for 'handoff-fire.sh' matches 42.6% of sessions purely because global CLAUDE.md quotes the command, and '/compact' matches 98.9% for the same reason.
- **Source:** `scratchpad/an3.py over s3_30.jsonl`

### `[MEASURED][GAP]` THE INSTRUMENT THE BRIEF HANDED ME IS WRONG: bare `input_tokens` is NOT the occupancy numerator. Under prompt caching its fleet median is 2 and its maximum across all 6,942 files is 28,540 — it counts only the uncached delta. True occupancy = input_tokens + cache_creation_input_tokens + cache_read_input_tokens. Every number below uses that sum.

- **Evidence:** an1.py on bare input_tokens: median 2, p99 10,368, max 28,540, zero sessions ≥100K. Re-scan with the three-field sum: median peak 134,657. bin/cc-ctx-audit:231 already sums all three ('summing only .input_tokens understates a long session by an order of magnitude'), but its own header at bin/cc-ctx-audit:12 still states 'Fill % = input_tokens / window' — the stale half is what propagated into this brief.
- **Source:** `/Users/chrisren/Development/claude-infrastructure/bin/cc-ctx-audit:12 vs :217-231; scratchpad/an1.py`

### `[MEASURED][STRENGTH]` PEAK-OCCUPANCY DISTRIBUTION of ended sessions (30d, n=2,904): p25 133K · median 190K · p75 276K · p90 429K · p95 558K · p99 754K · max 976,626. 46.1% exceeded 200K (so were provably on a 1M window); 11.7% exceeded 400K; 0.6% exceeded 800K. The fleet is running COOL, and cooling: p95 falls 558K (30d) → 475K (14d) → 433K (7d), p99 754K → 713K → 660K, and there were ZERO deaths in the last 7 days.

- **Evidence:** scan3.py occupancy max per file; trend computed by last_ts age buckets.
- **Source:** `scratchpad/an3.py, s3_30.jsonl`

### `[MEASURED][STRENGTH]` DEATHS: exactly 5 sessions / 8 'Prompt is too long' events in 30 days (0.17% of ended sessions), one per account plus one repeat — .claude-next 4fe8d91c (2 events), .claude-secondary 526aa752 (1), .claude-tertiary 8a34082e (2), .claude-quaternary c786f80f (1) and 076a1186 (2). Every event lands in the last ~1% of its transcript (e.g. lines 1880/1891 of 1896; 3403/3408 of 3413), confirming DEAD-IN-PLACE. All 5 had peak occupancy ≥400K and 4 of the 5 ≥800K. Only ONE death is in the last 14 days (2026-08-02).

- **Evidence:** JSON-parsed: requires isApiErrorMessage==true AND 'Prompt is too long' in the assistant message text. A raw fixed-string grep returns 146 files / 314 hits — 96% of those are sessions QUOTING the string while working on this very problem.
- **Source:** `scratchpad/toolong.py output`

### `[MEASURED][GAP]` THE LARGE-SESSION CUT (peak ≥400K, n=341): 22.6% recycled, 9.1% fired a handoff, 21.4% self-closed, 25.8% closed on a rung message, 19.6% just stopped with no rung and no act, 1.5% died. Recycle rate is strongly size-responsive — 0.3% in the 0-100K band, 1.5% at 100-200K, 3.5% at 200-400K, 16.6% at 400-600K, 35.8% at 600-800K — which is real evidence the DISCIPLINE works. It is also the ceiling: even in the 600-800K band, 40% of sessions still ended without any succession act.

- **Evidence:** per-band classification table in an3.py.
- **Source:** `scratchpad/an3.py`

### `[MEASURED][GAP]` THE KNOWN FAILURE IS REAL AND MEASURED: 41 ended sessions (1.4%) end with a final message announcing a recycle/handoff and NO fire in the tail; 21 of those 41 have no successor session started in the same project within 15 minutes. The failure is concentrated at the top — the five highest-occupancy cases sit at 730K-854K. Their transcripts end mid-sequence: 68aeeab0 says '84% — recycling now', writes /tmp/desk-recycle-bridge.txt, and stops; 80184a10 says 'we're at 82% ... instead of recycling', edits its brief, and stops; d50adab4 says 'Firing autonomously as a --recycle', runs `cat > /tmp/fire-zero-setup-100p.txt` (result: 'fire file: 2284 bytes'), and stops. None of the three ever invoked handoff-fire.sh. None hit an API error — they simply produce no further turn.

- **Evidence:** Tail dumps of the five sessions printed from the raw JSONL; last tool_use in each is a Write/Edit/heredoc of the successor brief, followed only by hook/system entries.
- **Source:** `scratchpad tail-dump over .claude-next/projects/…/{68aeeab0,80184a10,d50adab4,a8715e47}.jsonl`

### `[MEASURED][GAP]` THE RAILS EXIST, ARE CORRECTLY DEPLOYED, AND DO NOT FIRE. Across three IDL rotations (~19h of live fleet operation): waiting-recycle.sh 19,742 evaluations → 5 'fired' (0.025%); boundary-handoff.sh 828 evaluations → 0 fired, 100% abstained. waiting-recycle's abstain reasons are dominated by ARMING, not by context: not-armed 3,238+5,611+5,535, disarmed 1,341+1,051, vs below-threshold-no-tell only 109+387+173. boundary-handoff abstains 'below-threshold:NN<73' with observed used_pct clustered at 27-37 and one 66, plus 15/249 'no-telemetry'.

- **Evidence:** ~/.claude/autonomy/idl.jsonl (live 5h window 01:28-06:27Z 2026-08-11) plus gunzip -c of idl.jsonl.20260810T082424Z.gz and idl.jsonl.20260809T172116Z.gz. The hook's own header records the historical version of this: hooks/waiting-recycle.sh:43 '0/2419 prod fires decomposed as 1977 not-armed'. The ARM-BY-DEFAULT remedy is scoped to a session holding the DESK role (hooks/waiting-recycle.sh:402) and ships SHADOW, so 15+ concurrent non-desk sessions remain uncovered — and 'not-armed' is still the #1 abstain reason today.
- **Source:** `~/.claude/autonomy/idl.jsonl; hooks/waiting-recycle.sh:40-43,247,402; hooks/boundary-handoff.sh:99,191`

### `[MEASURED][STRENGTH]` Running bytes match HEAD — this is NOT a stale-deploy case. ~/.claude/hooks/waiting-recycle.sh, ~/.claude/hooks/boundary-handoff.sh and ~/.claude/bin/cc-ctx-audit are per-file symlinks into the checkout and are byte-identical to the worktree tree; all three are registered in ~/.claude/settings.json (lines 561, 826, 806 for session-continue).

- **Evidence:** cmp -s of live path vs repo path for each; rg over ~/.claude/settings.json.
- **Source:** `~/.claude/settings.json:561,806,826`

### `[MEASURED][GAP]` THE DENOMINATOR IS STILL MISSING, AND THE DURABLE BACKUP IS EMPTY + POLLUTED. Model id carries no window marker (only 'claude-opus-5' / 'claude-opus-4-8' / 'claude-fable-5' appear; no '[1m]' variant exists anywhere in the corpus), so the window is unrecoverable from the transcript. cc-ctx-audit's durable fallback ~/.claude/autonomy/recycle-events.jsonl holds 2,545 rows of which only 30 have a real session id — the other 2,515 are TEST rows (sid 's5', 'fw1', …) written into the LIVE store, and all 2,515 carry window:null. Live ephemeral telemetry currently covers 45 sessions: 43 at window 1,000,000, 1 at 200,000, 1 null.

- **Evidence:** rg over model strings in the corpus; python census of recycle-events.jsonl by sid length; per-file read of /tmp/cc-telemetry/*.json.
- **Source:** `~/.claude/autonomy/recycle-events.jsonl; /tmp/cc-telemetry/; bin/cc-ctx-audit:194-209`

### `[INFERRED][GAP]` The denominator gap has a bounded, quantified blast radius rather than being unbounded: 50.0% of ended sessions peaked above 190K, and a session on a 200K window at 190K is at 95% fill while looking like 19% under the 1M assumption. Live telemetry says 1 in 45 sessions is on a 200K window (2.2%), so the expected exposure is roughly 1% of ended sessions mis-read as cool — small, real, and currently invisible.

- **Evidence:** Occupancy CDF (>=190K: 1,451/2,904) × live window mix (1/45 at 200,000).
- **Source:** `scratchpad/an3.py + /tmp/cc-telemetry census`

### `[MEASURED][STRENGTH]` Manual /compact is effectively extinct and is NOT the fleet's coping mechanism: only 3 of 3,037 sessions carry an isCompactSummary entry (0.1%), and '/compact' appears as an actual slash-command invocation 79 times against 378 for /goal and 217 for /effort. This corroborates CONTEXT_ECONOMY_V2's finding on a fresh 30-day window and with a cleaner instrument.

- **Evidence:** scan3.py counts isCompactSummary==true via JSON parse and slash commands via <command-name> tags, not raw substrings.
- **Source:** `scratchpad/an3.py`

## Unknowns

- Why the 41 announced-but-never-fired sessions stopped producing turns: none of them recorded an isApiErrorMessage, so the cause is either pane kill, process death, operator abandonment, or a silent harness stop — the transcript cannot distinguish these, and the distinction decides whether the fix is atomicity or supervision.
- The true window for the 54% of ended sessions that never exceeded 200K peak. Model id carries no [1m] marker, telemetry is ephemeral, and the durable fallback store is 98.8% test rows — so fill% is uncomputable for half the population and every policy threshold (35/50/75/85%) is unenforceable there.
- Whether the IDL's ~5-hour rotation window is representative of arming state over 30 days. I verified three consecutive rotations (~19h, consistent: 0.025% fire rate, not-armed dominant) but did not read the full 30-day archive, and no per-session arming history exists further back.
- Whether the quoted memory cost model (MB = 228 + 0.343 × K-input-tokens, n=21, R²=0.71) was fitted on bare input_tokens or on true occupancy. If bare, the regressor has a fleet median of 2 and the coefficient is meaningless; the model needs re-fitting on input+cache_creation+cache_read before it can be used to argue that a static cap and recycling discipline reach the same memory outcome.
- Whether a session file is one session: --resume and crash-recovery may fork a new sessionId, which would inflate the session count and could misclassify a resumed session's original file as 'just stopped'. I did not reconcile transcript files against the session registry.
