# Gap G2: FileChanged + `watchPaths` as a 0-token push channel for idle panes

Date 2026-10-18. Scope: the D3/D20/#11 delivery gap and the cost of the `statusLine.refreshInterval` option (#8 option, Wave 3.5, 6.2).

**Deviation from the brief.** I did **not** run the live probe. Its three steps need a scratch settings.json, scratch hook scripts and a launched `claude` process. The same brief's HARD RULES forbid all three: "READ-ONLY everywhere except your ONE output file" and "editing any settings*.json". Everything below comes from a static read of the running binary, the docs and the transcripts. §5 is the probe, written out to run as is. Every claim the probe must settle is marked **[probe]**.

Binary used throughout: `B=~/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe`. All 46 live sessions run 2.1.293 [M: `ps -axo command= | rg -o '^\S*claude[^ ]*' | sort | uniq -c` → 40 `.bin/claude` + 6 `claude.exe` under `~/.claude-293`].

## 1. What the binary does (static, [M] = `rg -a -o` over `$B`)

| # | Fact | Evidence (rg pattern) |
|---|---|---|
| F1 | The watcher is created once at **setup**, before the REPL, from the settings snapshot. It arms only if some path is named: `initialize` → `he()` → `_e()`, logged as `setup_file_watcher_ms`. | `XKo(o,n,v),hr("setup_file_watcher_ms"` |
| F2 | Static watch list: each FileChanged group's **matcher** is split on `|`. Absolute values are kept as they are (`Rvo(Rt)?Rt:xvo(n,Rt)`) and relative values are joined to cwd. Matcher-less groups add nothing to the list, but they run for every watched path (the match query is the file's basename, via `IVe(e.file_path)`). | `for(let vt of Ze){if(!vt.matcher)continue;…` · `case"FileChanged":return IVe(e.file_path)` |
| F3 | chokidar options: `persistent:true, ignoreInitial:true, awaitWriteFinish:{stabilityThreshold:500,pollInterval:200}`. Events: `add`, `change`, `unlink`. **`ignoreInitial`**: a file that already exists when the watch arms fires nothing. | `Kb.watch(Ue,{persistent:!0,ignoreInitial:!0,…})` |
| F4 | SessionStart `watchPaths` are collected from each hook result that **completed** (`xe.push(...Ye.watchPaths)`). After the whole loop they are applied with `Q0t(xe)` (replace) or `J0t` (add). If the SessionStart signal is aborted (`if(q?.aborted||Y?.aborted)return Te`), every path is dropped. A cancelled hook yields no parsed JSON, so **its watchPaths are lost**, like the rest of its output. A sibling's paths survive. | `xe.push(...Ye.watchPaths)` … `if(xe.length>0)if(_e)J0t(xe);else Q0t(xe)` |
| F5 | **The watch from F4 arms only after the last SessionStart hook resolves.** In the incident shape, that is the moment the harness cancels the dispatcher. An alert written by the cancelled hook's TERM trap therefore races the arming, and F3 suppresses it if it wins. **[probe]** | ordering in `JY()` |
| F6 | Change handler: `a3r()` → `nrn()` → `fO()`. It reads only `watchPaths` and `systemMessage`; nothing is yielded to the transcript, so **0 model tokens**. Each systemMessage goes to `M?.(msg,false)`, and a failed hook's output goes to `M?.(out,true)`. **`M` is null until the prompt footer mounts and registers it**, so an event before mount drops its toast silently. | `for(let Qe of st)M?.(Qe,!1);for(let Qe of Ye)if(!Qe.succeeded&&Qe.output)M?.(Qe.output,!0)` |
| F7 | **Toast lifetime: 5,000 ms (success) or 8,000 ms (failed hook)**, `priority:"low"`, `key:"env-hook"`. | `ro({key:"env-hook",kind:"event",text:xo,color:Co?"error":void 0,priority:Co?"medium":"low",timeoutMs:Co?8000:5000})` |
| F8 | **Same-key de-duplication.** `addNotification` returns unchanged state if a notification with that key is current or queued. A second FileChanged (or CwdChanged) message for the same session inside the 5 s window is **silently dropped**. | `if(!(!new Set(t.notifications.queue.map((c)=>c.key)).has(r.key)&&t.notifications.current?.key!==r.key))return t` |
| F9 | `fO()` also emits the universal **`terminalSequence`** field (`bye(Hn,_e)` → `oMe` → terminal write). The allowlist is OSC 0/1/2/9/99/777 plus BEL. This is a **persistent** operator signal: a kitty tab bell mark or a desktop notification. kitty is the running terminal [M: `ps -axo comm= \| rg -i kitty`]. | `function bye(e,n){…oMe(r)…}` inside `fO`; docs hooks.md "Emit terminal notifications" |
| F10 | `XKo` is skipped only when `Fn()` is true, so `-p` and SDK sessions also arm. The docs say the systemMessage "doesn't reach the SDK message stream", and the terminalSequence is "only while its interface is on screen". | docs hooks.md FileChanged/CwdChanged output |

Docs (curl `code.claude.com/docs/en/hooks.md`, 2026-10-18): FileChanged "runs the hook no matter what changed the file … a process outside Claude Code entirely". It "starts the watcher only when something names a file to watch". "Give the group that handles dynamic paths an omitted matcher". "In interactive sessions, it shows the `systemMessage` as a brief terminal notification."

## 2. What the three probe questions resolve to statically

1. **Does it render in an idle pane?** Probably yes: the footer mounts at the idle prompt and registers `M`. **[probe]**
2. **How long does it stay?** **5 s** (F7) [M static]. A second alert within 5 s is dropped (F8). In the incident, the dispatcher was cancelled at 05:50:01.703Z and the first user record came at 05:56:23.581Z: **6 min 22 s idle** [M: `rg '"hookEvent":"SessionStart"'` + first `"type":"user"` in `~/.claude-secondary/projects/-Users-chrisren-Development--worktrees-wt-cc-004752-67086/5759497b-….jsonl`. The session moved from quaternary.] A 5 s toast at 05:50:02 is gone long before anyone looks, so **the toast alone does not close D20.** The persistent part has to be `terminalSequence` (F9): a BEL marks the kitty tab, and OSC 99 posts to Notification Center.
3. **Are a cancelled hook's watchPaths lost?** **Yes** (F4) [M static]. Seeding from every sync hook still fails when all of them are cancelled. In the census list, session `54b18e51` had **all four** sync hooks cancelled (desk-brief-inject, dod-persist, mailbox-drain, dispatcher) [M: `xargs rg '"hook_cancelled"'` over `/tmp/startup-hooks-census-files.txt` → jq SessionStart → `/tmp/g2-cancels.tsv`: 54 (session,hook) cancels in 41 sessions. Dispatcher cancels: 4 in the files still present; 4 of 411 listed files have moved since, the incident's among them.] Seeding from desk-brief-inject alone would have worked for the incident, which recorded no desk-brief cancel. It would have failed for 54b18e51, so **1 of 5 known dispatcher-cancel sessions** [M: the 4 above plus the incident]. It also conflicts with README 6.6, which proposes retiring desk-brief-inject. **Conclusion: do not seed from SessionStart.** Use F2 instead: put an absolute alert *directory* in the FileChanged matcher. The watch then arms at setup (F1), before any SessionStart hook runs. No hook has to survive, and the F5 race goes away (alerts are written after the watch is up).

## 3. Cost: FileChanged push vs `statusLine.refreshInterval`

| Channel | Standing cost | Per-fault cost | Latency to operator |
|---|---|---|---|
| `refreshInterval = R s` (c10) | 46 sessions × ~11 execs × ~57 ms CPU per render ÷ R. **R=1: ~506 execs/s, ~2.6 cores. R=10: ~51 execs/s, ~0.26 cores. R=60: ~8 execs/s, ~0.04 cores** [E: product of the measured 46 sessions; 10-11 execs/render (`docs/research/load-root-cause-2026-10-17/D-hooks-statusline.md:29`, code read); 56.1-57.7 ms CPU/render (`docs/plans/LIMIT_DETECT_100P.md:789,1117`, P6 getrusage)]. Today the machine-wide rate is 0.30 renders/s (D-hooks-statusline.md:28). | 0 | ≤ R s, persistent |
| FileChanged on a static alert dir | 46 idle fs watches, ~0 CPU [E: chokidar fs.watch, event-driven] | 1 hook spawn per session per alert (all 46 watch the shared dir; each hook exits unless basename == its `session_id`). 41 alerted sessions/2 d × 46 ≈ **1.9k spawns/2 d ≈ 0.011/s** [E: from the measured 41] | ≤ 0.5 s stability + spawn; toast 5 s, terminalSequence persistent |

R=10 costs about **4,600× more spawns** than the push channel (51 / 0.011) [E]. The repo has already refuted refreshInterval: `docs/plans/LIMIT_DETECT_100P.md:466` ("1 s × 16 panes × 61 ms/render = one core, permanently — refuted (P6)"). It is also exactly the standing per-session poller that README:230-231 rejects ("every daemon is new load"). `~/.claude/statusline.sh` is 680 lines, with 31 `jq` and 14 `git` call sites [M: `wc -l`, `rg -o '\bjq\b' | wc -l`, `rg -o '\bgit\b' | wc -l`].

## 4. Changes to the README

| # | Change | Impact | Effort | Risk | settings.json | Conviction |
|---|---|---|---|---|---|---|
| G2-1 | **Drop `refreshInterval`** from #8 option, Wave 3.5, 6.2, D20's "Loud by" column, and #1 "Optional". If kept at all, state its cost: 46 × 11 / R execs/s (~0.26 cores at R=10). | Avoids 8-506 execs/s standing load [E] | S (doc edit) | none | removes one c10 item | 90 |
| G2-2 | **New c10 migration: register FileChanged.** Group A: `matcher` = absolute dir `~/.claude/state/startup-health/alerts` (expanded; arms the watch at setup) plus a no-op hook. Matcher-as-regex never matches a basename, so A's hook never runs **[probe]**. Group B: no matcher, `startup-alert-notify.sh`, timeout 5. The hook uses builtins only and no jq. It reads stdin, exits 0 unless `basename(file_path) == session_id`, then prints `{"systemMessage":"⚠ startup: <hook> … · <recovery>","terminalSequence":"\a\e]99;;startup fault <sid8>\e\\"}`. One rolling alert file per sid, with every pending line in it, because F8 drops a second toast. | D3, D20 and #11's late-outbox losses become operator-visible within ~0.5-1 s instead of at the next prompt: 5 known dispatcher-cancel sessions plus the D1 cancels in 41 sessions/2 d, now pushed [M counts]. 0 tokens (F6). | M | Medium. The F2 absolute-matcher path, chokidar recursion on a dir and the kitty OSC 99 render are all unprobed. Fan-out spawns are bounded by the fault rate. | **yes (c10, operator-only)** | 65 (85 after §5 passes) |
| G2-3 | **Writers:** #11's TERM trap and late collector, and #8's sentinel path, write `alerts/<sid>` (temp + `mv`). The ledger/outbox stays the durable record, and #8's first-prompt line stays as the backstop for anyone who missed the toast or bell. | as G2-2 | S, on top of #8/#11 | Depends on README **Q2**: if the harness sends SIGKILL rather than TERM, no trap writes. D1 for dod-persist and mailbox-drain then has no pusher and stays first-prompt only. | no | 70 |
| G2-4 | **#19:** **forward** child `watchPaths` (union) instead of refusing. Closes latent D8 for that field. Not needed by G2-2, which uses no SessionStart seeding. | D8 latent → closed | S | none | no | 75 |
| G2-5 | **Do not seed watchPaths from SessionStart** (not from desk-brief-inject, not from every sync hook). F4 + F5 + the 54b18e51 all-four cancel [M] make it lossy exactly in the incident shape. | avoids a channel that fails in 1 of 5 known dispatcher-cancel sessions | — | — | — | 80 |

D20's "Loud by" column becomes: "FileChanged toast (5 s) + terminalSequence tab bell / OSC 99, pushed by the alert writer; first-prompt line as backstop". This also answers README Q15 (agent-spawned panes nobody watches): the push costs nothing when nobody looks, and the ledger still records the fault.

## 5. The probe (not run; operator or an authorised worker runs it)

Follow the R5b pattern (`docs/research/R5b-sessionstart-render-probe.py`: pty.fork, `--setting-sources project`, a scratch project dir with `.claude/settings.json`), with these changes: binary `~/.claude-293/node_modules/.bin/claude`, and a scratch `CLAUDE_CONFIG_DIR` copy so no live account dir or transcript dir is touched. Settings:

- `SessionStart`: a sync hook printing `{"hookSpecificOutput":{"hookEventName":"SessionStart","watchPaths":["$P/alerts/sidA"]}}`, and a second sync hook that sleeps past a 2 s timeout, traps TERM, and prints a watchPath `$P/alerts/sidB`.
- `FileChanged`: group A with matcher `$P/alertdir` (absolute) and hook `true`; group B with no matcher, printing `{"systemMessage":"ZZFCZZ <basename>","terminalSequence":"\u0007"}`.
- A background writer: at t+1 s `echo x > $P/alertdir/s1`; at t+4 s `echo x > $P/alerts/sidA`; at t+4.5 s `echo y > $P/alertdir/s2`, inside the 5 s window; at t+20 s `echo z > $P/alerts/sidB`. No prompt is ever typed. Capture the pty for 30 s.

Pass criteria:

- (a) `ZZFCZZ s1` appears: the static absolute-dir watch arms at setup and the toast renders in an idle pane.
- (b) `ZZFCZZ sidA` appears: SessionStart watchPaths work.
- (c) `s2` is absent while `sidA` is current, which confirms F8.
- (d) Time between the s1 render and its erase is about 5 s (F7).
- (e) `ZZFCZZ sidB` is absent, which confirms F4 (a cancelled hook's paths are lost).
- (f) The BEL byte count rises per event.
- (g) The TERM marker exists or not, which answers Q2.
- (h) The scratch transcript contains no `ZZFCZZ`, confirming 0 tokens.
