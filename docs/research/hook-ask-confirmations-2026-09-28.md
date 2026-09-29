# Hook "confirm intent" prompts: what is recorded, how many, and what to change

wf_64053140-014 (5 investigators, 2 verifiers). Instruments are archived in `docs/research/hook-ask-confirmations-2026-09-28/instruments/` (originally run from /tmp/hookask-verify and /tmp/hookask-curl; `analyze.py`/`scan.py` are the curl ones). Sources: **T** `/tmp/hookask-verify/census*.py` (deduped transcripts) · **C** `/tmp/hookask-curl/analyze.py` over `~/.reso/curl-audit.jsonl` · **W** `/tmp/hookask-verify/tpl.py` · **X** exact `cleared_tool_use_id` join to `~/.claude/autonomy/permission-archive/` · **J** `/tmp/hookask-verify/join*.py` (±15 s) · **V** `/tmp/hookask-verify/ver.py` · **R** `/tmp/hookask-verify/rmcmd.py` · **O** `/tmp/hookask-other/census2.txt` · **H** `cc-permission-harvest 30 --json` · **L** `~/.claude/logs/validate-bash-decisions.jsonl`.

## 1. The answer

**(a) No. No store records every Proceed click with its hook, reason, command and outcome, and none records which button was pressed.** For sessions on Claude Code 2.1.260 or later, the transcripts hold everything except the button.

| Store | Hook | Reason | Command | Outcome | Button | Join key |
|---|---|---|---|---|---|---|
| `~/.reso/curl-audit.jsonl` | curl-gate | yes | redacted | no | no | tool_use_id |
| `validate-bash-decisions.jsonl` (from 2026-09-10) | implied | yes | **no** | no | no | sid + time |
| pr-gate | no log | | | | | |
| Beacon archive | no | no | yes | inferred | no | `cleared_tool_use_id` (grant only) |
| `permission-denied.jsonl` | 0 hook asks; all 443 rows are auto-mode classifier denials | | | | | |
| Transcripts (`hook_success` + `tool_result`) | yes | yes | yes | yes | no | toolUseID |

- **The beacon sees most hook asks.** It has a row for about 92% of curl-gate asks (2,427/2,635) and about 64% of validate-bash asks (740/1,159) (J).
  It misses auto-denied asks, and because it is keyed on session id alone, a concurrent prompt overwrites the first (`cc-permission-beacon.sh:72,434`).
- **A grant can be proved, but nothing uses the proof.** `cleared_tool_use_id` equals the ask's id on 1,339 asks, and matches 0 of the 32 curl denials (X).
  `permission_matcher.py:1277-1279` ignores it, and `:1271` maps Stop to "refused", yet 99 of 99 Stop rows joined to a hook ask ran (J).
- **Transcripts are complete only on newer versions, and only recently.**
  On 2.1.220, 1,355 of 1,447 curl asks left no attachment; on 2.1.260+, nearly all did. 1,019 of 3,129 curl asks predate retention (~2026-08-17) (V).
- **300 asks were never shown to anyone.** Each was denied in under 1 s, with no archive row and no permission-denied row (T).
  Trigger: a hook ask plus a safety-check ask in a context that cannot show a dialog (2.1.284 binary). 258 were `rm -r` on literal /tmp paths.
- **Which button was pressed** exists only in a native `tool_decision` event (sources `user_temporary`, `user_permanent`, `user_reject`). OTEL export is not configured, and whether the event reaches OTEL was not tested.

**(b) Telemetry: yes. Build one ledger, filled from the transcripts, with no new capture in the hot path. Conviction: 75%.**

- **Row** (`~/.claude/logs/hook-ask-ledger.jsonl`, one per tool_use_id): `hook, reason, cmd, cwd, outcome (ran | user_rejected | auto_denied | unknown), shown, wait_s`; the last two from the `cleared_tool_use_id` match.
- **Filler:** a read-only miner over `hook_success` attachments and `tool_result`s, run at harvest time. Dedupe by toolUseID (245 ids sit in 2-3 account dirs, T); skip the symlinked `~/.claude-next/projects`.
- **Hooks must log:** validate-bash adds tool_use_id, redacted command, cwd; pr-gate adds a one-line log; curl-gate already suffices. This covers missing transcripts.
- **Fix alongside:** matcher uses `cleared_tool_use_id` alone; drop Stop→refused for hook asks; key the beacon on sid + tool signature and keep `permission_suggestions`.
- **Alternative rejected.** Hook logs joined to PostToolUse cannot show denials, because PostToolUse never fires for a denied command.
- **Button:** test whether `tool_decision` reaches OTEL first.

## 2. Census

**By hook, 2026-08-17 to 2026-09-29 (T; verifiers differ by 1-2):**

| Hook | Asks | Ran | Operator said No | Auto-denied |
|---|---|---|---|---|
| validate-bash | 1,733–1,734 | 1,432–1,433 | 2 | 299 |
| curl-gate | 739–740 | 738–739 | 0 | 1 |
| pr-gate | 4 | 4 | 0 | 0 |

**curl-gate, own log** (442 synthetic 2026-09-10 replay rows excluded):

| Window | Asks | Classes | Outcome |
|---|---|---|---|
| All time (since 2026-05-19) | 3,105 (C) | GET to an unknown host 2,063 (retired 2026-08-24) · "confirm intent" 182 (5.9%) | 2,048 granted · 31 No · 1 denied · 1,025 unknown |
| Last 30 days | 712 (W) | No URL parsed 468 · credential 119 · POST confirm 103 · non-HTTP 19 · method 3 | not measured |
| Since edaaa897d (2026-09-25 02:22Z) | 151 (C) | No URL parsed 76 (58 from one session) · POST confirm 36 · credential 33 (24 from a cookie jar) · non-HTTP 5 · method 1 | all 151 ran |

Since the 2026-09-25 fix (edaaa897d, newest curl-gate commit), "No URL parsed" is half of all asks: the URL sits in a loop variable, `$(...)` or heredoc. A parser gap, not host policy.

**validate-bash by class (T):**

| Class | Asks |
|---|---|
| rm on a variable target | 700 |
| rm on a relative path | 509 |
| rm on an absolute path | 287 |
| git reset --hard | 144 |
| rm on a misparsed shell token | 66 |
| git clean -x | 15 |
| git restore | 5 |
| git stash drop | 3 |

Its own log holds 1,159 real asks and 19 test rows (L).

**Waits** (wall-clock, not attention):
- Exact join (X): median 165 s for validate-bash and 27 s for curl.
- Curl, last 30 days (C): median 18 s, p90 360 s, 119.7 h in total.
- validate-bash, all shown asks: about 964 h in total (O).

**Refusals.** 2 for validate-bash (T); 31 of 2,110 for curl (1.5%, C/T), all on 2.1.220; 0 since the fix.

**The harvester undercounts.** It marks 364 prompts as hook-raised (H), but 1,196 of 2,869 (41.7%) are, by exact join (X). The cause: it classes a prompt as "structural" before checking for a hook (`bin/cc-permission-harvest:763-786`).

## 3. Scalable pattern

**A settings.json allow rule cannot clear a hook ask:** the hook runs first, and its ask survives an allow rule (live test on 2.1.260, `docs/research/permission-prompt-census-2026-09-10.md:41-46`; 2.1.284 binary). The modal's "settings.json to update hooks" only names where the hook is declared. And curl-gate's "allow" is no decision: relaxing it hands the command to the auto-mode classifier. The levers are inside the hooks:

| Candidate | Where | Evidence | Verdict |
|---|---|---|---|
| Resolve URLs in loop variables, `$(...)` and heredocs | curl-gate parser, `:832` | 76 of 151 post-fix (C) | **Do** |
| Stop treating `EOF`, `}`, `done` as rm targets | validate-bash tokenizer | 66–79 asks (T, O) | **Do** |
| Check `--connect-to`, `--resolve`, `-x`, `--socks*` | curl-gate `decide()`; flags parsed at `:271-359`, never checked | a bypass of the host check | **Tighten** |
| Drop port 4040 (the ngrok API) from `is_localhost_dev` | `:660-666`, runs before the method check | a POST to it opens a public tunnel | **Tighten** |
| Find why the mktemp resolver still misses | validate-bash (608155c7e) | 23 asks after the fix (R) | Investigate |
| Add a reviewer | pr-gate `--reviewer` | 4 asks (T) | No change |

**Refused or dangerous:**
- **A host allowlist for POST "confirm intent".** Rejected on 2026-08-23 because the hosts form a tail of 382 (`permission-prompts-2026-08-23.md:47-54`). Kept as-is on 2026-09-24 (`PERMISSION_PROMPT_CONSOLIDATION.md:79`).
- **Image-search uploads** (bing, lens, yandex `upfile=@$F`, baidu). They upload local file bytes to a third party.
- **Publishing hosts, auth hosts, and Turso**, where a POST runs SQL.
- **Loopback writes.** 17 of the 18 POSTs to 127.0.0.1 hit safaridriver WebDriver, which drives a real browser. 1 PUT hit Chrome DevTools. The operator rejected 2 of 27 loopback writes (curl-audit + transcripts, verifier).
- **rm on /tmp-bound variables (243), relative rm after `cd /tmp` (341) (R), and literal /tmp paths.** Live infrastructure lives in /tmp; this was decided on 2026-09-10.
- **A `Bash(curl:*)` allow rule.** Auto mode drops it, and it cannot clear a hook ask anyway.
- **Cookie-jar GETs.** Not analysed; hold.

## 4. Verifier corrections

| Claim | Corrected |
|---|---|
| 2,696 transcript asks / 1,887 attachments | 2,480–2,482 distinct |
| 231 asks never shown | About 285–300 |
| Transcripts are complete | Only on 2.1.260+ and from 2026-08-17 |
| Joins are by time only; a grant leaves no trace | `cleared_tool_use_id` and the transcript prove grants |
| Stop means refused | For hook asks, Stop is almost always a grant (1 exception) |
| Reasons exist only in hook logs | Transcripts hold them too |
| 30-day curl counts 727/226/140/20/3 | 468/119/103/19/3; replay rows were included |
| 3,529 curl asks | 3,126 real |
| 1,170 real validate-bash asks | 1,154 |
| Beacon join counts 2,392 and 3,039 | Upper bounds; joining on the command gives 2,092/2,634 |
| 350 rm variables unresolvable | 63 of about 666 |
| Loopback writes are safe | Refused (§3) |
| validate-bash has 4 ask sites | 7 sites, plus curl-gate 7 and pr-gate 1 |
| `:908` fires for unknown hosts | It fires for PUT/PATCH/DELETE to any host |
| Commits 6bf610045 and 834bd7b5d | Landed as d8b517b28 and 608155c7e |
| Backlog item 08bfe39cb4c5 is pending | Stale |
| A hook "allow" bypasses all checks | Deny and ask rules are still checked (2.1.284) |

## 5. Open questions

| Question | Conviction |
|---|---|
| Does `tool_decision` reach OTEL? | 55% yes |
| Is "don't ask again" offered on hook asks? | 40% yes |
| What causes the 132–168 unarchived asks that had no concurrent prompt? | 50% a beacon failure |
| Were the curl waits of 2 s or less in August human clicks? | 30% |
| Do auto-deny and a human No always leave different result text? | 80% |
| Does the ≤1.9% hook ceiling still hold? | 25% |
