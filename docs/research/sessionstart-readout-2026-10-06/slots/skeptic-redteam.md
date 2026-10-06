# Skeptic red-team of synthesis-draft.md (ranked changes)

Worktree b87e6da64; live board/logs read 2026-10-06 ~06:50-06:55Z. M = measured (command run here), R = reasoned from code/log reading.

| rank | refuted | conv | reason (citation) |
|---|---|---|---|
| 1 | no | 82 | M: `floor(k)` wrong for 29/57/58, `round` exact, tenth always .0; 4,146 wire readings, max 2 dp. Concern: after the change, nearly-out (E100/W0.99) and plain endpoint-99-wire-miss both print `99%` with bar `▆▆▆▆▆▆▆▁` (`pct_text(99.0,None)` → "99%", `board_bar` :6418 caps at 7 cells), and the 18 (E99,W0.99) rows get no sentence (`:6745` needs `weekly_pct>=100`), so colour-off loses the "server consulted" cue d6c4f8411 promised. Not an H3 breach (not one of the three wall states), but a glyph decision the operator must make knowing it. |
| 2 | no | 92 | M: jsonl 44469 s=2 (03:08:26, first 0.99) → 44577 s=7; r2 §91 "3-4 5h-pp, n=8, never ≥5". Formula at `:6748-6750` confirmed. |
| 3 | no | 80 | M: probe log 06:01:41.857 wire aw → marker `rate_limit__next3.jsonl:45` 06:02:42Z (60 s). Read time has a source today: `_quota_age_s` cache ts (`:2687`), only computed under `if narrow:` (`:6582`); tick wall p50 5.6/p90 23 s (r4) sits between read and cache ts, absorbed by HH:MM. `k_work` None on 29/105 readings needs fallback wording. W-11 check (3) already passes "under 1% left, possibly none" (no "of the week"); only (2),(4) need retargeting. |
| 4 | no | 94 | M: variant diff = line 164 only; shellcheck rc 0; `/bin/bash` 3.2.57 on the live 2,190-byte board 0.82/0.82/0.82 s → 0.00 ×3 (load 14.7); 5/5 inputs same E/N verdict. |
| 5 | no | 85 | M: fragment regexes as described; cc-bats run still owed (r7 §4). Line pins :206/:207/:209/:336/:341/:358 confirmed by grep. |
| 6 | no | 68 | M: live board 01:50 CDT prints `0% of the week left` and `⚠ WALL trajectory` under "out of weekly quota, confirmed". R: pace_line's own rationale (§5.2, ~:4500: "dropping a warning glyph off a warning is a strict loss") must be re-argued; core :2065-2069 pins WALL on wire-less rows only, so stays green. |
| 7 | no | 93 | M: err log 1 ItimerError, mtime 2026-09-30T17:02:42-0500; `:5835`→`:5861`→`:5750`; keepwarm passes no max_wait so `deadline` starts None (`:5794`). Test design valid: `lock_wait_s` 5 (`accounts.json:25`) is the degrade arm, `fresh_lock_wait_s` 240 the second loop; ItimerError is uncaught → rc 1, FreshLockWedged → rc 5 (`:8267-8273`). |
| 8 | no | 90 | M: 3/3 live PATHs put /opt/homebrew/bin before /bin (pids 32870, 8514, 33373). Marker :45 06:02:42Z; 06:02:41.736Z survives only in r3b-apierr-lines.txt — the e131c8d2 .jsonl is gone from ~/.claude-tertiary/projects. Cite the marker as the durable source. |
| 9 | no | 60 | M: `:1961` only writer. Unlisted consumer: `_place_fact_live` `:5042-5062` expires a rejected fact when a wire read dated later says allowed; it keys on `read_at`/`at`/`wire_at`, none written by `fetch_wire_limits` (`:1316-1327`), so stamping activates a dormant `--place` branch; `claude-accounts-place.bats:178` exercises it only with a synthetic `read_at`. Needs a place test. |
| 10 | no | 75 | M as rank 8. Risk: a session launched by a launchd-scheduled peer gets launchd's PATH (rule "Deployment interpreter ≠ yours"); none observed live. |
| 11 | no | 70 | M: `tests/accounts-board.bats:57-60` runs `"$HOOK"` via shebang → PATH bash; test 14 comment :282-300 shows wall-clock bounds are coin flips under taskpolicy. |
| 12 | no | 45 | R: `--max-age 90` kick inside 90 s serves cache (`:5796`) but still `write_board` (`:7814`), so the fold works; bare kickstart is a no-op on a running tick (`stop-failure-marker.sh:287`), tick p50 5.6/p90 23 s of 185 → ~3-12% kicks lost (estimated). The arm's existing kick is default-OFF by design (`:284-289`); the proposal must say why keepwarm is exempt. Limited arm sits above the cap exit (`:230`, `:632`). |
| 13 | no | 45 | Unverifiable on disk; no new evidence. |
| 14 | no | 65 | M: probe 06:03:49 rejected vs jsonl 44581 06:08:11 (262 s). `record_utilization(rows)` lacks `prev`; available at `:5859`. |
| 15 | no | 55 | M: `git show d6c4f8411` hunks touch board_eff/pct_text/readout_lines only; "/accounts table" = readout. `render_table :7023` uses plain `bar/pct` (`:6012/:6032`). Consistency fix, not an H3 requirement. |
| 16 | no | 65 | M: hook `:72` "CAP STAYS 500 … ruled § 11 #7 at 85%"; `:632` early exit; `cc-limited:93` 5000. Aligning down is consistent with that ruling. |
| 17 | no | 70 | M: print at `:7817-7821`, no ts. |
| 18 | no | 55 | `…-surpassed-threshold` appears in no log or code (grep); record all `anthropic-ratelimit-unified-*` keys rather than a named one. |
| 19 | no | 45 | r3a §32 confirmed (median 4, n=10). Producer would read a 14.5 MB jsonl per tick; cost unmeasured. |
| 20 | no | 55 | M: freshness `:285` pins present tense "accepting work". |
| 21 | no | 50 | No test pins output == file byte-for-byte (grep); re-measure stands. |
| 22 | no | 45 | M: 97/500 recent ticks served-cache (19%); r4's 2/113 is the lock-degrade subset only. |
| 23-25, 27, 29 | no | as drafted | No new evidence. |
| 26 | no | 65 | M: binary string is "rounded percentage or reset time moves"; `:1228` upper-cases ROUNDED as round-UP evidence it does not give. |
| 28 | no (REJECT stands) | 5 | M: `WEEKLY_FLOOR` 0.005 `accounts.json:51`; `w_rem <= floor` at `:4698`, `:4917`. |
| 30-33 | no | as drafted | r3a §30-32, §149 (2.2×); `next2.7d.json` first_sid 4ad354fc (a next3 session, marker :49); plist :20, :83-84, :89. |

## Missed
- The (E99, W0.99) band (18 rows) has no note sentence at all; rank 1 removes its last textual distinction.
- Rank 8's plan correction should cite the marker (06:02:42Z); the transcript source is gone.
- Rank 9 touches `--place` semantics; no rank lists a place test.
- Rank 12 must reconcile with the hook's deliberately gated kick arm (`:284-289`).
