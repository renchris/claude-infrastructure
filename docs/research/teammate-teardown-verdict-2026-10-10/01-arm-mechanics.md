# 01 — arm mechanics: what the RETIRED arm keys on, and why cvf-docs missed it

Slot: arm-mechanics · 2026-10-10 · read-only investigation. Code read at worktree HEAD `16b6b441f`.
`~/.claude/hooks/lead-crash-watchdog.sh` resolves to `~/Development/claude-infrastructure/hooks/lead-crash-watchdog.sh`, and `diff -q` against the worktree copy prints IDENTICAL. The last commit to touch the file is `c3d5a71dc` (2026-10-01), so the live daemon (spawned 17:53:56Z) ran this exact code.

## Answer in one paragraph

The RETIRED arm keys on exactly one signal: a `type:"user"` / `message.role:"user"` record in the dead session's **own** transcript. That record's content must hold `<teammate-message` and the literal `"type":"shutdown_request"`, with a `requestId` ending `@<member-name>`, and the session must be a teammate (argv `LEAD_AGENT_ID` or `teamName`+`agentName` on its records). The record appears only when the member's runtime injects a queued inbox message into the conversation at a **turn boundary**. cvf-docs drained its inbox 0.78 s after the lead's SendMessage returned: the inbox mtime is 18:04:26.984Z and the file is now `[]`. At that moment it was in the middle of a Bash tool call (tool_use at 18:04:26.867Z, no tool_result). TaskStop came at 18:04:50Z, SIGTERM at 18:04:59Z, and the process exited at about 18:06:27Z. It never reached a turn boundary, so the request was never written to its transcript. The fallback that might have named the kill (`external-sigterm`) needs a close record, and Agent-Teams members launch the raw `claude.exe` without `bin/cc-close-attrib`, so no close record exists. The cause therefore fell to `abrupt-unknown`, and the renderer drew the `⛔ KILLED` headline. Separately from the cause, it used the `▶ Teammate … is not resumable` reopen line, because `tm_is=1` came from argv.

## (a) teammate_facts / retired_teammate

`hooks/lead-crash-watchdog.sh`:

- `:340` `teammate_facts()` streams the transcript in one python pass (`:343`, argv = transcript and `${LEAD_AGENT_ID:-}`) and prints `TEAMMATE<TAB>NAME<TAB>TEAM<TAB>SHUTDOWN`.
  - TEAMMATE: `name` is taken from argv `<name>@<team>` (`:345-348`), or set by any record with both `teamName` and `agentName` (`:359-362`).
  - SHUTDOWN: a record counts only if `type=="user"` and `message.role=="user"` (`:364`). String content is used as-is; list content is joined from `text` blocks only (`:366-368`). The content must contain `"<teammate-message"` and `'"type":"shutdown_request"'` (`:369`). Then `shut = any(rid=="" or name=="" or rid.endswith("@"+name))` (`:375`).
  - SHUTDOWN=1 requires `is_team and shut` (`:376`).
- `:383` `retired_teammate()` returns 0 iff field 1 == 1 **and** field 4 == 1.

So prose mentions do not count. The transcript has 5 lines containing `shutdown_request` (`grep -c shutdown_request` ⇒ 5). Lines 10 and 322 are attachments. Lines 88, 129 and 357 are `tool_result` blocks: a python check on them prints `['tool_result'] has <teammate-message: False`. None of them qualifies.

**Replay of the matcher** (the same python predicate, run on the three teammate transcripts of team session-247fdf36):

```
== f959926c (cvf-readout)  match line 179 2026-10-10T18:00:46.692Z rid= shutdown-1791655236738@cvf-readout
== d2a47de0 (cvf-hooks)    match line 658 2026-10-10T18:12:06.258Z rid= shutdown-1791655925285@cvf-hooks
== 5b813b72 (cvf-docs)     (no match)
```

## (b) Callers, and how the headline is chosen

| caller | line | reached when | effect |
|---|---|---|---|
| classify_death arm 0 | `:556-557` | only if `find_close_record "$pid"` returns a record **and** `map_exit_class` maps its exit code (`:538-545`) | relabels the class to `RECYCLE\tretired-teammate` (jetsam still outranks it) |
| classify_death arm 1.4 | `:584-586` | no usable close record, no jetsam | prints `RECYCLE\tretired-teammate` |
| pane_verdict_text | `:1449`, `:1459-1464` | always | reads field 1 (`tm_is`) and field 2 (`tm_name`) only; `tm_is==1` swaps the **reopen/resume lines** for `▶ Teammate $tm_name is not resumable: tell its lead … the lead re-spawns members` |
| pane_verdict_text headline | `:1466-1467` | `case "$class:$cause"` | **only `RECYCLE:retired-teammate`** gives `✅ RETIRED — teammate $tm_name … was shut down by its lead`; every non-RECYCLE class without collected custody gives `⛔ NOT A CLEAN EXIT … KILLED` (`:1513`) |

So the headline is selected by the **cause string** produced by classify_death, never by `tm_is`. That is why the painted banner is internally split. The renderer knew this was a teammate (argv), which produced the reopen line, but it drew the KILLED headline because the cause was `abrupt-unknown`. `handle_crash` passes classify_death's output straight through (`:1903` ⇒ `:1958` paint_pane_verdict).

**Replay of the renderer** (`--pane-verdict` entrypoint, `CC_PANE_VERDICT=0` so nothing is painted, `HOME` set to a mktemp dir, `GIT_OPTIONAL_LOCKS=0`):

```
=== as classified: CRASH abrupt-unknown
⛔ NOT A CLEAN EXIT — Claude session 5b813b72 was KILLED here (verdict painted …).
   cause: abrupt-unknown. It did not exit and nothing closed it. The
   exit text above offers a resume line; ignore it — a teammate is not resumable outside its team.
   work in /Users/chrisren/Development/.worktrees/close-verdict-first: unlanded:16 · its last close verdict: no
▶ Teammate cvf-docs is not resumable: tell its lead (session 247fdf36) — the lead re-spawns members
▶ Or triage first:  cc-husk-sweep --pane 200
=== counterfactual: RECYCLE retired-teammate
✅ RETIRED — teammate cvf-docs (session 5b813b72) was shut down by its lead; its work went to the lead (verdict painted …).
   This pane holds nothing: close this pane (Ctrl-D). It is not resumable — its lead re-spawns members.
```

The first block reproduces the live banner text. The live log line is `[2026-10-10 13:08:04] … pane verdict PAINTED on ttys019 (pane 200): ⛔ NOT A CLEAN EXIT …` (local time is CDT, so 18:08:04Z).

## (c) Why the cause was abrupt-unknown and not external-sigterm

- The ladder's tail (`:665-671`): `cause="abrupt-unknown"`, raised to `suspected-oom-large-context` only if kb>4096 (here kb=1159), and to `external-sigterm` only if `ec == "143"` (`:670`). `ec` is set **only** from a close record at `:540`.
- **There is no close record for pid 23017.** `ls ~/.claude/logs/close-records/23017-*` ⇒ `no matches found` (the store holds 1498 records). The crash row agrees: `{"ts":"2026-10-10T18:07:03Z","sid":"5b813b72-…","pid":23017,"class":"CRASH","cause":"abrupt-unknown",…,"exit_code":"","signal":"",…}` (`~/.claude/logs/claude-crashes.jsonl`). The death page says the same: "NO close record was written for pid 23017".
- Why there is none: the lead's own `ps` at 18:04:37Z shows the member's argv as `23017 /Users/chrisren/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe --agent-id cvf-docs@session-247fdf36 --agent-name cvf-docs --team-name session-247fdf36 … --parent-session-id 247fdf36-…`. That is the raw binary with no `cc-close-attrib` wrapper, which matches what the file itself says at `:166-167` and `:327-329`.
- **cc-pane-runner records the exit code nowhere the watchdog reads.** `bin/cc-pane-runner:310-313` captures `_rc`, and `_close_on_exit` only `printf`s `cc-pane-runner: %s exited %s — keeping a shell …` to **stderr**, i.e. the pane (`:180`). A grep for file redirections or `mv`/`tee` (excluding `>&2`) finds no writes. `find_close_record` (`:176-199`) reads only `${CC_CLOSE_RECORDS_DIR:-~/.claude/logs/close-records}/<pid>-*.json`, which only `bin/cc-close-attrib:317-319` writes.
- Even with a close record, 143 would **not** have produced RETIRED: `map_exit_class` returns 1 for 143 by design (`:423`), so the death falls through to the ladder and lands as `CRASH external-sigterm` unless arm 1.4 fires. This is replay C2 below.

## (d) How the watchdog learns of a teammate's death at all

- The teammate's own SessionStart runs this hook, so the member is watched as its own "lead": `LEAD_PID=$PPID` (= 23017). Watchdog log: `[2026-10-10 12:53:56] registered session=5b813b72-… pid=23017 tty=ttys019 pane=200 teammate=cvf-docs@session-247fdf36` and `spawned watchdog daemon pid=24877`.
- `LEAD_AGENT_ID` is captured at registration from argv via `agent_assignee_argv` with `CC_WF_START_PID=$LEAD_PID CC_WF_MAX_HOPS=1` (`:1689-1700`; seam `CC_PANE_VERDICT_AGENT_ID` at `:1310`). Here it is `cvf-docs@session-247fdf36`, so `teammate_facts` field 1 = 1 and the name is known regardless of the transcript.
- Pidfile: `$WATCHDOG_DIR/$sid.pid`, where `WATCHDOG_DIR` is hard-coded to `$HOME/.claude/watchdog` (`:86`) for every account. The daemon `local_watchdog` (`:1794`) polls every 30 s with `lead_alive` (pid + lstart pin).
- Two detection paths exist. Path 1, `pid file gone AND lead pid … gone` (`:1820`), is taken after a clean SessionEnd, because `hooks/session-end.sh:177-180` removes the pidfile. Path 2, `LEAD CRASH detected` (`:1844`), is taken when the pidfile is still present. **cvf-docs took path 2**: log line `[watchdog 5b813b72-…] LEAD CRASH detected pid=23017`. `grep 5b813b72 ~/.claude/logs/sessions.log` ⇒ nothing, so SessionEnd never logged for it. Both siblings logged `Session ended sid=… reason=other` (13:01:00 and 13:12:14 CDT) and took path 1.
- `handle_crash` ⇒ `classify_death "$sid" "$pid"` with **no death epoch** (`:1903`), so jetsam is judged against "now" (fine on the live path).

## Replays of classify_death (`--classify` entrypoint, `:1597-1601`)

The `--classify` entrypoint exits before stdin is read or the pidfile and daemon code run. Its only write is `mkdir -p $HOME/.claude/{watchdog,logs}` (`:132`), so `HOME` was pointed at a mktemp dir in every run. Stores were overridden with `CC_CLOSE_RECORDS_DIR`, `CC_TEARDOWN_DIR`, `CC_REGISTRY_DIR`, `CC_HANDOFF_LOG`, `CC_JETSAM_DIRS` and `LCW_WATCHDOG_ENV=`. Death epoch = 1791655587 (18:06:27Z, see the timeline). Output columns: CLASS, CAUSE, KB, RECORDS.

```
A  real stores read-only, argv id as live            CRASH   abrupt-unknown      1159 390
A2 same, death=auto                                   CRASH   abrupt-unknown      1159 390
B  fully isolated empty stores                        CRASH   abrupt-unknown      1159 390
   sibling cvf-readout (f959926c, pid 72313)          RECYCLE retired-teammate     716 194
   sibling cvf-hooks   (d2a47de0, pid 96664)          RECYCLE retired-teammate    1929 672
C1 copy of real transcript + ONE appended delivered   RECYCLE retired-teammate    1160 391
   shutdown_request user record (shape copied from cvf-hooks line 658, requestId shutdown-1791655466065@cvf-docs)
C5 no argv id, real transcript                        CRASH   abrupt-unknown      1159 390
C5b no argv id + appended record                      RECYCLE retired-teammate    1160 391
C2 synthetic close record exit 143 only               CRASH   external-sigterm    1159 390
C3 close record 143 + appended record                 RECYCLE retired-teammate    1160 391
C2b synthetic close record exit 137 only              CRASH   killed-oom-or-force 1159 390
C2c close record 137 + pid-keyed teardown marker      RECYCLE retired-by-desk     1159 390
C4 pid-keyed {"mode":"teardown"} marker, no record    CRASH   abrupt-unknown      1159 390
C4b same marker keyed on sid                          RECYCLE deliberate-teardown 1159 390
```

What the replays show (measured):

- A and B reproduce the live verdict exactly, from the real transcript.
- The one variable that flips it is the delivered shutdown record (C1, C5b). The argv id is not needed (C5b), and a close record alone gives `external-sigterm`, which is still a CRASH (C2).
- A pid-keyed teardown marker is consulted only inside arm 0, via `retired_by_desk` (`:307-321`), so it does nothing without a close record (C4). A sid-keyed marker hits arm 1.5 (C4b). The 1.5/1.6 arms do not check `mode` at all. Only `retired_by_desk` requires `"mode":"teardown"` (`:316`).
- Real stores held no marker: `ls ~/.claude/watchdog/teardown | grep -E '5b813b72|23017|^200\.json'` ⇒ rc 1, and a content grep for 5b813b72 found no files. No handoff row: `grep -c 'prev_sid":"5b813b72' handoffs.jsonl` ⇒ 0. No stderr log for 23017. Registry `~/.claude/cc-registry/200.json` still names 5b813b72.

A harness error in my first pass, now corrected: the Bash tool runs zsh, which does not word-split an unquoted `$ISO`. So `env $ISO …` set `HOME` to the whole string, the store overrides were ignored, and C2/C4b/C5 first printed `abrupt-unknown` wrongly. Those runs also left empty nested directories under `$TMPDIR` (0 files, deleted with `find … -type d -empty -delete`). Every row in the table above comes from the explicit-assignment rerun.

## Why the request never reached the transcript (timeline, measured)

| UTC | source | event |
|---|---|---|
| 18:03:24.595 | teammate tx line 323 | cvf-docs SendMessage "cvf-docs DONE: commit eec712aee" |
| 18:03:41.243 | teammate tx line 337 | lead's relay "relay doc passages from REPORT" lands, and cvf-docs starts follow-up edits |
| 18:04:16.915 | lead tx line 815 | lead receives the 18:03:24 DONE (the lead was busy) |
| 18:04:21-24 | teammate tx 383-385 | Edits to CLAUDE.global.md and hooks/lib/why-tier.sh (follow-up work) |
| 18:04:25.438 | lead tx line 820 | SendMessage `{"type":"shutdown_request","reason":"eec712aee merged into close-verdict-first"}` |
| 18:04:26.207 | lead tx line 828 | result `Shutdown request sent … Request ID: shutdown-1791655466065@cvf-docs` |
| 18:04:26.867 | teammate tx line 386 | Bash tool_use (a grep in the cvf-docs worktree). **This is the last conversational record; it has no tool_result.** |
| 18:04:26.984 | `stat -f %Fm inboxes/cvf-docs.json` | the inbox is rewritten to `[]` |
| 18:04:50.929 | lead tx line 843 | TaskStop ⇒ `Successfully stopped task: t5ou0rn4u … task_type: in_process_teammate` |
| 18:04:55 | lead tx line 853 | `ps` still shows 23017 |
| 18:04:59.336 | lead tx line 857 | `kill -TERM 23017` (the process is still alive at 18:05:00, 18:05:07 `S+`, 18:05:25 and 18:05:56; load average about 221) |
| ≈18:06:27 | teammate tx lines 387-390 | trailing `bridge-session`/`cost-state`/`last-prompt` records. `startTime 1791654833767 + totalDuration 753659 ms` ⇒ 2026-10-10T18:06:27.4Z, which is when the exit flush ran |
| 18:07:03 | claude-crashes.jsonl | watchdog classifies: CRASH abrupt-unknown |
| 18:08:04 | watchdog log (13:08:04 CDT) | pane verdict PAINTED on ttys019 |

The inbox-drain-then-hold pattern can be seen on the sibling. cvf-readout's inbox mtime is 18:00:37.521Z, but its transcript record (line 179, where the shutdown_request is batched with a relay message) is stamped 18:00:46.692Z, 9 s later, at its turn boundary. For cvf-hooks the two stamps fall in the same second: 18:12:06.327Z and 18:12:06.258Z. **Inference, not measured:** the cvf-docs process read and cleared its inbox, held the shutdown_request in memory as a pending turn input, and died before the next turn boundary. That would leave the request in neither the inbox (now `[]`) nor its transcript.

## Other signals this death carried that the code could have used

1. **The argv teammate identity** (`LEAD_AGENT_ID=cvf-docs@session-247fdf36`, captured at registration). It is already used, but only for the reopen line, never for the cause.
2. **The lead's transcript.** It holds the SendMessage `shutdown_request` tool_use plus a success tool_result with `request_id shutdown-1791655466065@cvf-docs`, the TaskStop, and `kill -TERM 23017`, all within 35 s before the death. It can be found from the team name: `session-247fdf36` gives the lead sid prefix `247fdf36`, and `find_transcript` already prefix-globs `"$sid"*.jsonl` (`:153`). The argv also carries `--parent-session-id 247fdf36-…`, but registration does not capture it. This is the only durable record that the request was **sent**. It does not show that the request was **received**.
3. **The member's inbox file** `~/.claude-quaternary/teams/session-247fdf36/inboxes/cvf-docs.json`: mtime 18:04:26.984Z, content `[]`. That indicates the member consumed something after the SendMessage, but the message itself is gone.
4. **Team config.** `config.json` members now list only team-lead, but its mtime is 13:12 CDT (18:12Z), after the 18:07:03Z classification. Whether cvf-docs was still listed at classification time is unmeasured.
5. **Absence of SessionEnd** for 5b813b72 (no sessions.log line), while the trailing cost-state flush **is** present. The process ran an exit path after SIGTERM, about 88 s after the signal under load ≈221, so this was not a SIGKILL or a binary crash.
6. **cc-pane-runner's `claude.exe exited 143`.** It goes to the pane's stderr only (`bin/cc-pane-runner:180`), so nothing is persisted.

**Caution for whoever designs the fix.** The `RECYCLE:retired-teammate` banner asserts "its work went to the lead … This pane holds nothing", and `pane_verdict_close` (defined at `:1560`) is triggered by that phrase (`:1545`). That claim would have been **false** here. `GIT_OPTIONAL_LOCKS=0 git -C ~/Development/.worktrees/cvf-docs status --porcelain` ⇒ ` M CLAUDE.global.md`, ` M CLAUDE.rules.slim.10-session-close.md`, ` M hooks/lib/why-tier.sh`. These are follow-up edits made after the DONE commit, at the lead's own 18:03:41Z request. The renderer's `work in` line could not have caught them, because it inspects `LEAD_CWD` = the session cwd `/Users/chrisren/Development/.worktrees/close-verdict-first` (all 298 `cwd` fields in the transcript), not the cvf-docs worktree where the edits are. Widening the arm to lead-side evidence alone would have turned this kill into a falsely clean "close it" verdict.

Incidental, outside this death: the team-scan loop in `handle_crash` (`:1973`) globs only `~/.claude`, `-secondary` and `-tertiary` `/teams/*/config.json`. `~/.claude-quaternary` is missing, so a quaternary **lead's** death (such as 247fdf36) would report "no teams affected".
