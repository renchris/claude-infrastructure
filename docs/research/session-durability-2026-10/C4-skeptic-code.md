# C4 skeptic: code and evidence

Skeptic pass on `C4-hybrids.md`, 2026-10-01. This pass was read-only apart from this file. I made 0 of the 3 allowed
`kitten @` calls, signaled nothing and did not launch `claude`. The experiments ran on private tmux servers
`-L sd-probe-c4sk-{a,b,c,d}` with `sh`/`sleep` dummies. All four were killed, and their socket files were removed by
name (`ls /private/tmp/tmux-501 | grep -c sd-probe-c4sk` => `0`). The two scratch source copies in /tmp were deleted.

## Answer

**No fatal flaw, and H1 still ranks first. But the dossier's main new finding is partly false, and one key claim
is refuted. Recommended conviction: 52 (the dossier says 62).**

- Citations check out. 30+ file:line references were opened, and every line number cited for the 7 key claims is
  right to within a line or two. All of the counts reproduce (43/32/49 files, 1,523 and 16,118 lines, 531 denial rows,
  535/382 September markers).
- **Weakened, and it matters: "no kitty socket is involved in delivery."** The ported injector depends on
  `lr_screen`, and `lr_screen` reads the pane through the kitty remote-control socket (`it2 session read` →
  `it2-kitty` → `kt get-text`). The port replaces about 31 `send-text` calls with up to about 10 `get-text` calls per
  nudged pane, made during the restore, when the new kitty's socket is busiest.
- **Refuted: E5's premise that "a socket file outlives a SIGKILLed kitty."** kitty 0.48.2 unlinks its socket from a
  separate `kitten __atexit__` helper that ignores signals. Measured: `/tmp/kitty-610` no longer exists after
  today's SIGKILL.
- **Weakened: the zero-command crash trigger.** The cited code is not pid-matched. The real 2026-10-01 event wrote no
  `.ips` file, so this trigger would not have fired.

## Verdicts on the key claims

| # | Claim | Verdict | Evidence (command => output) |
|---|---|---|---|
| 1 | The classifier refuses acting on other live sessions, including `tmux kill-session`. Self-retirement is allowed. | **stands** | `python3` scan of `~/.claude/logs/permission-denied.jsonl` => 531 rows. All 9 cited timestamps reproduce with the quoted `input_head`: 09-09T07:06:15Z `tmux kill-session -t lr-resume-9e3074fc` "Blocked by classifier"; 10-01T19:13:40Z `[Remote Shell Writes]`; 09-26T22:07:11Z send-text; 10-01T16:40:09Z/16:45:03Z `cc-pane-close`. Marker count by `ts[:7]` and `mode` over `~/.claude/watchdog/teardown/*.json` => 2026-09 `terminal` 535, `recycle` 382. Nit: of the two "self-close blocked" rows, 09-10T02:57:52Z was "Stage 2 classifier error … transient" and 09-26T06:11:56Z was `--allow-dirty` judged `[Irreversible Local Destruction]`. Neither is a refusal of self-retirement as such. |
| 2 | Porting lr-fire-resume's launch-time injector into reso-resume-one fixes the 30-of-31 undelivered nudges, with no agent and no kitty socket involved. | **weakened** | The line numbers are right: READY arm `lr-fire-resume.sh:1248-1262`, `proc lr_submit_cr` `:1035`, quiet arm `:1267-1293`, `reso-resume-one:560` spawn, `:712` shell. **But the screen oracle uses the socket.** `LR_SCREEN_SH` runs `"$LR_IT2" session read -s "$LR_PANE"` (`:833`). `LR_IT2=$HOME/.claude/bin/it2` (`:803`) execs `it2-kitty` whenever `KITTY_WINDOW_ID` is set (`~/.claude/bin/it2:111-118`). `session read` is `kt get-text --match id:…` (`it2-kitty:1465-1469`), and `kt` is `kitty @ --to $CC_TERM_KITTY_TO` (`it2-kitty:207-210`). There are 4 `lr_screen` call sites (`:1044`, `:1280`, `:1295`, `:1384`), and `lr_submit_cr` polls once a second for up to 8 s (`:1037-1052`). With a deaf or breaker-tripped socket the oracle returns UNKNOWN: the quiet arm then types nothing (`:1290-1292`), and the CR goes out unconfirmed (`:1056-1060`). That failure is safe, but the "zero socket" claim is false. **The port is not ~80 LOC.** `reso-resume-one`'s expect (`:536-695`) has none of `LR_SCREEN_SH` (`:828-865`, 38 lines), `lr_screen`/`lr_pump`/`lr_note`/`lr_say` (`:968-1015`), `lr_submit_cr` (`:1035-1062`), the pane id and the nonce/tail needles (`:809-827`), or the submit-confirm loop (`:1300-1440`). The probe it calls is a separate 163 lines (`wc -l lr-submit-probe.sh`). **"Proven" overstates it.** The same file records three stranded-prompt incidents after the design existed: 2026-09-22 coalesced CR (`:1017-1029`), pane 751 "TASK-LESS for hours" (`:815`) and pane 815 (`:823`). The simpler path is real: the binary has `.argument("[prompt]","Your prompt",String)` (`grep -a` on the 2.1.284 `claude.exe`), and the docs list `claude -r "<session>" "query"`. The dossier's `strings => [prompt]` hit is ambiguous, because the first `[prompt]` matches are slash-command `argumentHint`s. |
| 3 | With tmux's alternate screen off, kitty's scrollback gets paced output in full; bursts are lossy. | **stands** (the burst count varies) | Re-run as a python pty client, `TERM=xterm-kitty`, 80 columns. `\e[?1049h` count: default 1, `terminal-overrides ',xterm-kitty:smcup@:rmcup@'` 0, which reproduces. Burst lines reaching the client: **46, 47, 45, 24** of 100 over four runs (the dossier has 23), so the loss is real but its size depends on timing. Paced: 60/60 in all four runs. The bytes around `PACE-30` are `\e[1;23r\e[23;1H\n\e[APACE-30\r\n`: an LF at the bottom of a region whose top is 0. kitty v0.48.2 `screen.c:2241-2248` (`screen_index`) and `:2261-2269` (`screen_scroll`) add a line to history when `linebuf == main_linebuf && margin_top == 0` (fetched from raw.githubusercontent). kitty's own history was **not** measured; that step is inferred from source. |
| 4 | Claude Code's background daemon is a vendor pty broker already outside kitty, but it conflicts with this fleet's identity and recycle machinery. | **stands** (as a watch item) | `ps -o pid,ppid,pri,etime,ucomm -p 9780,…` => `9780 1 31 29:02 claude.exe`. `ps -o lstart= -p 9780` => **14:17:33, 48 min after the 13:29:45 relaunch**, so it shows detachment only, not surviving a kitty death (the dossier's open question stands). Its `bg-pty-host` children serve **spare** sockets (`…/spare/*.pty.sock`, with `bg-spare` grandchildren). The roster supervisors for tertiary (52436) and quaternary (22624) are dead (`ps` => empty). 52436 predates the Sep 30 15:26 boot (`sysctl kern.boottime`). `handoff-fire.sh:4935-4975` (`hf_bg_hosted` at `:4960`) and bg-semantics Q1/Q3/Q5 verified. Softening: `hooks/session-register.sh:173-181,270` already restores the pane address of a bg fork "by lineage", so "every pane-keyed hook loses its address" is too strong for registry-keyed readers (env readers still lose it). |
| 5 | H1 touches only launch path (ii); H2 must migrate all three, and the identity surface is wide. | **stands** | Verified: `cc-pane-runner:77` `_id="${KITTY_WINDOW_ID:-}"`, `:192`, `:268`, `:281`, `:330`; `lib/claude-launcher.zsh:221` `claude() {`; `~/.zshrc:451` `claude() {`; `~/.zshrc:694-695` exports `ITERM_SESSION_ID="w0t0p0:$KITTY_WINDOW_ID"` behind `cc-in-kitty`; `cc-resume-layout.sh:257`, `:266`. `grep -rlE … bin scripts hooks lib \| wc -l` => 43 / 32 / 49; `wc -l bin/it2-kitty` => 1523. The 49 is a floor: the pattern misses `"$KITTY_BIN" @` (for example `cc-resume-layout.sh:175`) and callers that go through `kt`. |
| 6 | The null option fails one-command; today's scripts are one-offs. | **stands** | `kitty-restart-supervisor.py:26` `LEAD_SID`, `:28` `OLD_KITTY = 610`; `kitty-restart-resume.py:24` `D = "/tmp/inboot-2026-10-01"`; `inboot-finish.py:17` `NEW = int(sys.argv[1]) if … else 48854`. Nit: NEW is taken from argv, so that one is parameterised, but `SELF_SID`, `D` and `OLD_KITTY` are not. The nudge send is one write of `prompt + "\r"` (`inboot-finish.py:107-119`, `kitty-restart-resume.py:350-362`). |
| 7 | A fixed `listen_on` path needs an unlink before relaunch, because the socket file outlives a SIGKILLed kitty. | **refuted** (premise) | `boss.py:230-237` binds without unlinking, confirmed identical to upstream v0.48.2 by `diff`. **But `:236` hands the path to `robust_atexit.unlink`.** `Atexit` (`boss.py:203-221`) spawns `kitten __atexit__`, whose `main()` calls `signal.Ignore()`, waits for stdin EOF (that is, kitty's death, SIGKILL included) and then does `os.Remove` (`tools/cmd/atexit/main.go:17-58`, v0.48.2). Measured: `ls -la /tmp/kitty-610` => `No such file or directory`; `ls /tmp \| grep -E 'kitty-[0-9]+'` => only `kitty-48854`; `ps … \| grep __atexit__` => `50196` under `48854`. Nothing in the restart scripts unlinks it (grep). The `handoff-fire.sh:1216-1219` line is prose; its "verified 2026-08-05" covers only `ls` rc on a made-up `/tmp/kitty-99999`. **The real hazard runs the other way:** with a fixed path, the old kitty's helper unlinks *that path* whenever the old process finally exits. A relaunch that binds first would lose its path, and the staged kdw4 kitty could never share it. |

## Other claims checked

| Claim | Verdict | Evidence |
|---|---|---|
| Crash trigger "only on a pid-matched kitty `.ips` (`cc-resume-classify.py:116-141`)" | **weakened** | `terminal_crash_epoch` (`:120-141`) matches by **filename timestamp** across 6 terminal names. Its docstring says "no .ips body is parsed" (`:121-124`), so pid matching would be new code that reverses that design. `ls ~/Library/Logs/DiagnosticReports \| grep -ic kitty` => **0**. The incident that actually happened (a deaf socket, then SIGKILL) writes no `.ips`, so the "zero commands" path for (a) would not have fired on 2026-10-01. |
| "H1 fixes all six" 2026-10-01 failures, including missing tombstones | **weakened** | The dossier's own open question says why 14 sessions wrote no tombstone is unknown, and that H1 "leans on the heartbeat". That is a workaround, not a fix. |
| H1 "removes the likely trigger" (P1, S2, then P2) | **weakened** | `C3-skeptic-code.md:62,83-85` puts EMFILE at about 50% and calls the S2 peer-pile-up rationale "not demonstrated". P2 needs the operator to adopt a patched build. |
| The heartbeat `cc-sessions --json` makes 0 kitty calls | **weakened** (inferred) | `cc-sessions:184-187` calls `it2 session list --json`. Under launchd there is no `KITTY_WINDOW_ID`/`CC_TERM`, so `it2:111-112` takes the iTerm2 arm. Zero kitty calls is plausible, but nobody measured it under launchd (also noted in `C2-skeptic-code.md:76`). |
| `.start` bug, reaper whitelist, shed line, `fs_osa`, holder count, load-term switch | **stands** | `alarm-reboot-prep.sh:52` appends `… kalloc1024_gb=…` to `.start`, and `boot-resume.sh:298-299` rejects any non-digit. `cc-reaper:713` `GARBAGE_WL=` has no `boot-resume`. `cc-resume-layout.sh:250-252` shed; `:177` `fs_osa`. `lr-lib.sh:509` `lr_holder_count`. `capacity-admit.sh:1115,1215,1250` `CC_ADMIT_LOAD_TERM`. |
| tmux `fatal("accept failed")` (`server.c:389`) | **stands** | tmux 3.6a `server.c:384-389`: EMFILE and ENFILE back off for 1 s; any other errno is fatal. |
| `teammateMode: iterm2` at `:1305` in all 4 dirs | **stands** | `grep -n '"teammateMode"'` => `1305: "iterm2"` in each of `~/.claude{,-next,-tertiary,-quaternary}/settings.json`. |
| `sample` can see `KittyPeerMon` (S1 gate) | **stands** | `child-monitor.c:2012 set_thread_name("KittyPeerMon")`; `husk-panes-2026-09-30.md:89` measured `sample 610`. |

## Fatal flaw

None. The weakened items each have a contained fix (below), and H1's core holds: the `.start` fix, restore mode, the
ledger, fullscreen by id, and a launcher-side nudge. The refuted item (E5) affects only an optional H2 step.

## Missed risks

1. **The nudge's screen oracle adds socket load and inherits socket deafness.** It makes up to about 10 `get-text`
   calls per nudged pane: one quiet-arm read, up to 8 in `lr_submit_cr`, plus re-check reads at `:1384`. All of them
   fall inside the restore window that Risk 4 already counts at about 100 RC calls, so the real total is more like
   200 to 400 (estimated: 12 to 31 nudged panes × about 10). If S2's breaker trips or the new talk thread dies, the
   quiet arm parks and the CR goes out unconfirmed. Fix: route `lr_screen` through `kitty-rc`, budget it, or prefer
   the positional `claude -r <sid> "<prompt>"` once one pilot shows it survives the resume-threshold dialog. The
   positional path needs no screen read at all.
2. **A fixed `listen_on` path races the old kitty's `__atexit__` unlink** (claim 7). An unlink-before-relaunch step
   would also orphan the socket of an old kitty that is deaf but still alive. If H2 ever pins the path, it has to wait
   for the old pid **and** its `kitten __atexit__` child to exit before relaunching.
3. **Detached tmux sessions are a measured hazard in this repo, and C4 cites the evidence without its lesson.**
   `lr-reset-poller.sh:657-664` records `lr-resume-52e35019` frozen on a permission prompt nobody could see, and five
   sessions "alive there, unattended, for up to ten days". The 09-09 `kill-session` denial in E1 was an agent trying
   to retire one of those orphans. H2 must guarantee that every surviving server is reattached or loudly listed after
   a kitty death. Otherwise it recreates orphans that are unanswerable and that agents cannot retire.
4. **tmux 3.6a leaves socket files behind after `kill-server`.** Measured: 4 of 4 `sd-probe-c4sk-*` sockets remained
   after `kill-server` + `waitpid`, and `tmux -L … ls` said "no server running". So H2's `cc-reattach` and any census
   must probe with `ls`, never with a file glob. The dossier's "probes liveness" design is correct, but it should say
   why.
5. **The crash trigger's evidence model does not fit kitty's real failure mode.** The fleet's documented kitty
   deaths are hangs plus SIGKILL, and those write no `.ips`. So (a) almost always lands on "page plus one command",
   not zero, and the zero-command claim describes a case that has not been observed.
6. **The nudge port is about 3x the cost estimate**: about 250 to 350 lines including comments, against the stated
   +80 (estimated from the line ranges above). That pushes H1 toward the top of its 1,100-1,300 LOC band or past it.

## Recommended conviction: 52

The dossier's structure and citations are sound. Line numbers are reliable, the counts reproduce, and the tmux
experiment replicates. I lower it from 62 for three reasons. Its headline new finding (a socket-free launch-time
nudge) is half true and costs more than estimated. Its zero-command crash path would not have fired on the one real
event. And one evidence chain (E5) rests on a code comment that kitty's own source and today's `/tmp` contradict.
