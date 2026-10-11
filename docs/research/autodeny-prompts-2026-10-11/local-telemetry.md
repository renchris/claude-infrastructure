# Local (non-transcript) records of timed auto-deny prompts — census

Scripts: /tmp/autodeny-census/scripts/*.py. Every number below is MEASURED by the named script unless marked "estimated".

## Answer: is there a telemetry record of all of them?
No, not locally. The complete record is the 1P event stream (`tengu_safety_check_dialog_auto_denied`, `_capped`, `tengu_auto_mode_denial_dialog_auto_denied`). It is sent to Anthropic: telemetry is not disabled, and the only local copy is the failed-to-send retry buffer, which holds none of these events. OTel is not configured. Of the local non-transcript stores, none is complete. The transcripts are the only complete local record for the safety-check kind.

Ground truth used for the coverage figures (tx.py, match.py: rg -F over the 4 project stores for the model-facing deny text): **62 unique safety-check denials** between 2026-09-29 and 2026-10-11. 48 were TIMED (tool_use to tool_result took 120–171 s, so the dialog was shown and expired). 14 were IMMEDIATE (0–1 s: capped after 3 per session, or no dialog). 52 of the 62 came from subagents. Versions: 2.1.284 (7) and 2.1.293 (55). The safety-check timer is not in the 2.1.260 binary and is in 2.1.284, so nothing earlier exists. 2.1.260 already has the denial-limit timed fallback.

## 1. 1p_failed_events buffer (tele.py, tele2.py)
- 50 files after realpath de-dup (~/.claude-next/telemetry is a symlink to ~/.claude/telemetry; -secondary, -tertiary and -quaternary have their own). 2,398 events from 50 sessions, 2026-08-18 to 2026-10-10, v2.1.220–2.1.293.
- Counts: safety_check_dialog_auto_denied **0**, safety_check_dialog_capped **0**, auto_mode_denial_dialog_auto_denied **0**, auto_mode_denial_limit_exceeded **0**. Feature-health names `permission_safety_check_timed_dialog` and `permission_auto_mode_denial_fallback` also **0**. The only permission-related events are tengu_auto_mode_decision (6), tengu_auto_mode_outcome (6), and feature_ok permission_auto_mode_classifier / permission_auto_approve_config (6 each).
- What the buffer is: a retry queue. A batch is written only when its export POST fails and is deleted once a retry succeeds. That makes it a survivor sample of network failures, not a log. Coverage: 50 sessions out of about 6,289 transcript sessions in the 4 stores (find count; about 0.8%). Its 6 auto-mode decisions compare with 622 classifier denials in the permission-denied ledger alone, so it holds well under 1% of events (estimated). Coverage against ground truth: **0 of 62**.

## 2. Debug logs (rg over ~/.claude*/debug)
- Only 6 files exist: secondary 1, tertiary 1, quaternary 4. ~/.claude/debug has just a dangling `latest`. Each covers 10–100 s of a `--debug` run, dated 2026-08-19 to 2026-09-11.
- "Classifier denial limit exceeded, falling back to prompting": **0**. Lines about the rm safety check or auto-deny: **0** (3 regex hits, all SessionStart-hook text, i.e. false positives).
- Retention: written only with --debug and not otherwise created. Coverage: none. Both timed kinds post-date these files.

## 3. Beacon permission archive (~/.claude/autonomy/permission-archive; arch.py, cand.py, match.py, prec.py)
- Schema (cc-permission-beacon.sh `archive`): {session_id, ts, resolved_ts, waited_s = resolution-hook time minus prompt time, resolved_by (PostToolUse | PostToolUseFailure | Stop | SessionEnd), cleared_tool, cleared_tool_use_id, tool_sig, cleared_tool_sig, tool_use_id (always ""), tool_name, tool_input, cwd}. A grant is only provable when tool_sig == cleared_tool_sig.
- 6,914 rows in 3,232 files, 2026-07-31 to 2026-10-11, 0 unparseable. resolved_by: PostToolUse 5,451, Stop 1,203, PostToolUseFailure 220, SessionEnd 40. Outcome: grant 1,715, not granted (Stop/SessionEnd) 1,243, collateral 206, unknown (no sig, rows before 2026-09-07) 3,750.
- waited_s histogram: 0–5: 1,880 · 5–15: 1,609 · 15–30: 558 · 30–60: 500 · 60–90: 274 · 90–110: 121 · 110–118: 46 · 118–125: 35 · 125–130: 28 · 130–140: 53 · 140–160: 86 · 160–200: 133 · 200–300: 238 · 300–600: 339 · 600–1800: 431 · 1800–3600: 167 · ≥3600: 416.
- Coverage against ground truth: **26 of 48 timed (54%)** and **0 of 14 immediate**, since no dialog means no PermissionRequest. All 26 rows are not-granted: resolved_by Stop 25, PostToolUseFailure 1. Their waited_s runs from 117 to 12,231 and only 3 fall within 110–150. The "waited_s near 120" signature does not work: a subagent's prompt is cleared by the parent's Stop, so waited_s measures time to the end of the parent turn, not the 120 s timer.
- Why 22 timed denials are missing: the beacon is one file per session_id (`$DIR/$SID.json`, written with `mv -f`). Parallel subagents share the parent sid, and the next prompt in the session overwrites a beacon that has not been archived yet.
- Heuristic scores, rows since 2026-09-29 (n=663):
  - not-granted and waited≥118: 107 flagged, 25 true (precision 23%).
  - plus an `rm` token: 15 flagged, 9 true (60%).
  - 118–200 s window: 24 flagged, 2 true.
- The 26 confirmed rows are in /tmp/autodeny-census/archive-autodeny-rows.tsv. The full candidate set is in cand-all.json (195 rows over the whole archive) and cand-rm.json (65).
- Can the beacon tell an auto-deny from a human deny? **No.** It never sees the outcome or the reason. Both look like "Stop, no matching PostToolUse". Only the transcript's tool_result text plus a gap of about 120 s separates them.
- Important for the allowlist: **38 of the 62 truth commands contain no `rm` token.** They trip on wrappers the checker cannot resolve: `bash -c '…'` and `/bin/bash -c` bodies, `"$@"` function runners (`wt(){ …"$@"…}`, `hf_bounded(){ "$@"; }`), `$AB …` (variable as command), `eval "$(sed …)"`, and `source <(…)`. The rest are `rm -f $D/*` or `rm -f dir/*` with variable or glob targets.

## 4. Other stores
- **permission-denied ledger** (~/.claude/logs/permission-denied.jsonl): 622 rows, 2026-09-08 to 2026-10-11, all in auto mode, all classifier reasons. Safety-check rows: **0**. The 2.1.293 help string says PermissionDenied fires "After auto mode classifier denies a tool call", so timed and safety auto-denies never reach it. 37 sessions had ≥3 classifier denials within 10 min; that is the precondition for the denial-limit fallback (estimated proxy for "consecutive").
- **Denial-limit timed fallback**: the count is not established. `rg -F "consecutive actions were blocked. Please review"` matched 9 transcript files, all of them binary-strings research and none a real event. The fallback's auto-deny reuses the classifier denial message, so it can only be found as a classifier-style deny with a tool_use to tool_result gap of about 120 s (a transcript pass). The beacon records it only as an unexplained not-granted row.
- **lead-supervisor IDL** (~/.claude/autonomy/idl.jsonl plus rotated .gz; idl.py): 38,480 `permission_pending` rows across 510 episodes, 2026-09-22 to 2026-10-11. It matched **35 of 48** timed safety denials, more than the archive because it sees beacons before they are overwritten. The first page came at age 124–2,431 s in every case. PERMPEND_NOTICE_S=120 equals the timeout, so **every page arrived after the auto-deny had already fired**. It then keeps paging a prompt that no longer exists until Stop.
- **cc-permission-harvest**: reads the beacon archive and has no logic for safety checks or auto-deny (grep found 0 hits). It was not run: its docstring measures the full pipeline at 1,045 s, and `--check`/`--falsify` only read a proposal. Existing logs are in ~/.claude/logs/permission-harvest.* (not analysed).
- **OTel**: no CLAUDE_CODE_ENABLE_TELEMETRY or OTEL_* in any settings.json or the shell env, so it is off. The auto-deny path calls `logDecision({decision:"reject",source:"config"})` (binary). Inferred, not verified: enabling OTel would log a tool_decision reject for each one, but it would not distinguish them from other config rejects.

## Coverage gaps (timed safety: 48, immediate/capped safety: 14, denial-limit fallback: unknown)
| store | timed safety | immediate/capped | denial-limit fallback | can identify kind |
|---|---|---|---|---|
| 1p_failed_events | 0 | 0 | 0 | yes (event name), but it is a failure residue |
| debug logs | 0 | 0 | 0 | yes for fallback (warn line), but only with --debug |
| beacon archive | 26 (54%) | 0 | some (not separable) | no |
| IDL pages | 35 (73%) | 0 | some (not separable) | no, and always late |
| permission-denied ledger | 0 | 0 | precondition only | n/a |
| transcripts (reference) | 48 | 14 | needs gap analysis | yes for safety (text) |
