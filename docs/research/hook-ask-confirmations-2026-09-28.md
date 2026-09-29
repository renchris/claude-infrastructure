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
| Stop treating `EOF`, `}`, `done` as rm targets | validate-bash tokenizer | 66–79 asks (T, O) | **Done** before this census: efc0ef253 (09-23) + b1867c26c (09-24); 0 of 259 rm asks after both went live. CORRECTED (2026-09-29) |
| Check `--connect-to`, `--resolve`, `-x`, `--socks*` | curl-gate `decide()`; flags parsed at `:271-359`, never checked | a bypass of the host check | **Tighten** |
| Drop port 4040 (the ngrok API) from `is_localhost_dev` | `:660-666`, runs before the method check | a POST to it opens a public tunnel | **Tighten** |
| Find why the mktemp resolver still misses | validate-bash (608155c7e) | 23 asks after the fix (R) | By design — the remaining asks are intended. CORRECTED (2026-09-29) |
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

## 6. Decisions (2026-09-29, workflow wf_225e9394-f08: one researcher + one skeptic per decision)

| Decision | Recommendation | Conviction | Deciding evidence |
|---|---|---|---|
| Fix validate-bash reading `EOF`/`}`/`done` as rm targets | **Skip — already shipped** (efc0ef253, b1867c26c) | 95% | 84 of 579 rm asks were misparses before; 0 of 259 after both went live |
| Probe whether the `tool_decision` event reaches OpenTelemetry, to record the button | **Skip** | 85% | The 2.1.284 binary shows it does, but a pure hook ask carries no permission suggestions, so the dialog offers only Yes/No; transcripts already hold Yes vs No |
| Tighten curl-gate | **Do**: normalize numeric IPs (decimal, hex, octal, IPv4-mapped IPv6) in `is_internal_host` and apply it to `--resolve`/`--connect-to` targets; ask on `-x`/`--proxy`/`--socks*`/`--unix-socket`; drop port 4040 from `is_localhost_dev` | 85% | Offline `decide_command()`: IMDS or LAN via `--connect-to`/`--resolve` or a numeric IP gets allow, defeating the "unconditional" deny; `smart-bash-allowlist` allows `--resolve`, so curl-gate is the only guard. At most ~5 extra prompts over 4 months |
| Fix curl-gate's loop-URL resolver | **Do, narrowed**: quote-aware glob check in `shell_bindings()`, per-iteration expansion in `expand_argv()`, and close the `for u; do` / backslash-continued / zsh `for u (…)` decoys; do not add `while read` or `((` | 83% | The resolver already exists (03e9a2c6a); a `?` inside a quoted URL disables it (88 of 92 recoverable asks). ~100 fewer prompts/month, 0 phantom allows in replay |
| Hook-ask ledger | **Fold into `cc-permission-harvest`**, no standalone file: exact join on `cleared_tool_use_id` reported as a hook × structural cross-tab; validate-bash logs `tool_use_id` + `cwd` (not the command); no pr-gate log | 77% | Harvest is the only reader of hook logs; 950 of 1,347 exactly joined hook asks are bucketed "structural" first. Disputed: "no archive row" is not "never shown" (851 of 1,160 unjoined asks ran after human-scale waits) |

### Round 2 (2026-09-29, workflow wf_2892d169-00b: researcher + skeptic, xhigh)

| Decision | Round 1 → round 2 | Outcome |
|---|---|---|
| Tighten curl-gate | 85% → **92–93%** | Past 90%, so **implemented** in a dispatched session. Every bypass reproduced through `decide_command()` and `main()`; the committed reso policy (a62839121) already says IMDS/RFC1918 deny and 4040 read-only, so the code had drifted permissive. Cost: 2 asks in 7,663 reso curl commands. Round 2 added: IPv6 link-local/ULA (AWS IMDSv6 `fd00:ec2::254`), env `*_proxy=`, `--doh-url`/`--dns-servers`, `CURL_HOME`/`XDG_CONFIG_HOME`/`HOME` curlrc redirect, nip.io/sslip.io and `metadata.google.internal`. `--resolve=` is not a real curl spelling. **Companion, equal priority:** `hooks/lib/smart-bash-allowlist.py` hook-allows `curl http://169.254.169.254/` in every non-reso project with the classifier skipped; it should defer (not deny) those shapes. |
| Fix the loop-URL resolver | 83% → **87–88%**, narrowed | Only the quote-aware glob check in `shell_bindings()` and per-iteration expansion in `expand_argv()`. **Drop the decoy-closing** (0 wins, 3 allow→ask regressions on the 45-day corpus). 127 wins on 8,058 rows; 0 phantom allows across 48 adversarial decoys; zsh word-splitting and globbing checked in a sandbox. Below 90% because the gain is latency only (0 refusals, every ask approved). |
| Record hook prompts | 77% (fold into harvest) → **82–84% for a write-time record** | Round 1's fold returns counts, but the operator asked for a record of each click. Recommended: validate-bash logs `tool_use_id`, `agent_id`, `cwd`, `transcript_path` (no extra fork); curl-gate adds `agent_id` and `transcript_path`; pr-gate gets one log line; a read-only `cc-hook-asks [DAYS] [--hook] [--outcome] [--json]` resolves outcome and wait via the archive's `cleared_tool_use_id`, then the transcript `tool_result`. No appender hook: no event fires on the reject path. Dispute: of 18 hook-attributed rejections, 16 were interrupts, not deliberate "No"s, so the write-time record's edge over transcript mining is about 1 ask a day. |

### Round 3 (2026-09-29, workflow wf_2e0ddba2-805; landed 767615fac)

The resolver fix went to 93% once round 3 found a live security hole on 49134c399. The Bash tool's shell is /bin/zsh, and zsh applies subscripts and history modifiers to an unbraced reference. So `"$u[1,8]169.254.169.254/"` and `"$u:s/ok.com/10.0.0.1/"` reached the metadata service and a private address, while the gate read them as a GET to ok.com and allowed them. 767615fac makes `$NAME[` and `$NAME:<letter>` undecidable, so they ask. Measured on zsh: `:a`, `:A` and `:P` resolve against the cwd; `:e`, `:h`, `:r`, `:t`, `:u`, `:s` and `:gs` rewrite the value; braced `${u}[1]` and `${u}:h` and a port such as `$h:8443` stay literal. The same commit adds the quote-aware loop-word check and per-iteration expansion, and does no decoy-closing. Replay of the 8,058-row corpus against trunk: 127 ask→allow (all 127 round-2 wins), 1 deny→ask (a former internal-error deny), 0 allow→ask, and 0 new allows to an internal target. Adversarially, round 2's 48 decoys plus 14 zsh cases went from 12 internal-target allows to 3. The 3 left (`alias curl=…`, `eval "$c"`, and positional `for u;`) are unchanged from trunk and excluded by decision. Tests: `curl-gate-*.bats` 1..94 and `smart-bash-allowlist-*.bats` 1..55, all ok. **Open, for the lead:** the fix does not close a wider, older hole. Any unresolved `$` in a URL's host is judged as a literal name, so `read H <<< 169.254.169.254; curl -s "http://$H/latest"` allows, and `$h.reso.gl` passes the reso.gl suffix allowlist. Closing it costs about 41 allow→ask rows in 45 days. It waits on the agent-context deny-with-reason research.
