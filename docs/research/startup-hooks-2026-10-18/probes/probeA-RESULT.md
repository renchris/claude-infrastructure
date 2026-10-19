# Probe A: FileChanged push into an idle pane (Wave 6.2, README §2 row #13a)

Date 2026-10-19. Binary `~/.claude-293/node_modules/.bin/claude`, **2.1.293** (`cc-claude-bin` and `--version`). Load average was ~295-320 on 10 cores during every run.

**Verdict: PASS.** The gating criteria (a), (b), (f) and (h) pass, and so do (c), (d) and (e). The Wave 6.2 migration is written and staged unapplied: `migrations/0071-filechanged-startup-alerts.sh`, with `hooks/startup-alert-notify.sh` and `tests/startup-alert-notify.bats`.

Script: `probeA-filechanged.py` (in this directory). Evidence: `probeA-evidence/run{1,2,3-seed}/` (`result.json` holds the verdicts and the raw hook log, `chunks.jsonl` is the timestamped pty capture, `screen-final.txt` is the last screen). Scratch only: HOME, `CLAUDE_CONFIG_DIR`, the project and the hooks were all under one `mkdtemp` dir; `--setting-sources project`. The scratch config has no credentials, so no API call was possible ("Not logged in").

## Results (run 2, idle, no prompt; run 3 repeats it with one argv prompt so a transcript exists)

| Criterion | Run 2 | Run 3 | Raw evidence (seconds from exec) |
|---|---|---|---|
| (a) static absolute-dir matcher arms at setup; toast renders in an idle pane | pass | pass | s1 written 1.7 s, group B ran 2.44 s, `ZZFCZZ s1` on screen 10.74-15.74 s |
| (b) SessionStart `watchPaths` arm a file | pass | pass | sidA written 21.4 s, B ran 21.42 s, on screen 21.45-26.44 s |
| (c) a second toast inside the 5 s window is dropped (F8) | pass | pass | s2 written 21.9 s, B ran 21.98 s, never on screen |
| (d) toast lifetime ≈ 5 s (F7) | 5.005 s | 5.002 s | s1 and sidA intervals above |
| (e) a cancelled SessionStart hook's `watchPaths` are lost (F4) | pass | pass | sidB written ~29 s, B never ran; control s3 at ~35 s did render |
| (f) one BEL per event | pass | pass | standalone BELs 2.448, 21.437, 22.005, 35.443 s, one within 20 ms of each of the 4 group-B runs, **including the deduped s2** |
| (g) TERM marker | none | none | see below |
| (h) 0 tokens | n/a (no transcript is written without a prompt) | pass | the 39 KB transcript records both SessionStart hooks (`hook_success`, `hook_cancelled`), was last written after every FileChanged event, and holds 0 `ZZFCZZ`; no file in the scratch config holds it |
| group A's own hook | never ran | never ran | an absolute matcher arms but is regex-tested against the basename, so it cannot dispatch |

## What the probe adds to gap-G2

1. **The toast can be late, and a late toast eats the next one.** In run 1 the s1 toast waited ~8 s in the notification queue behind the startup `◐ medium · /effort` notice (group B ran at 3.45 s; the toast appeared at 11.7 s). F8 drops a key that is *queued* as well as one that is current, so sidA, written at 9.9 s, vanished. This is why the writes in runs 2-3 are 20 s apart (the §5 schedule put sidA inside s1's window, so (b) could not have passed as specified). Consequence for 6.2: the toast is unreliable in the first ~10 s of a session and within 5 s of another `env-hook` toast. **The BEL is not**: it is written per hook run, deduped toast or not (f). The design was already "toast plus `terminalSequence`"; the probe shows the bell is the half that always arrives.
2. **(g), README Q2: at the hook timeout the harness signals the hook's children, not the hook.** The SessionStart hook with `timeout: 2` was `/bin/bash ss2.sh`, whose parent was the `claude` process itself. At ~1.95 s its `sleep` child exited with rc 143 (SIGTERM), while the bash process caught **no** signal: it trapped TERM, INT, HUP, PIPE, USR1, USR2 and QUIT and none fired. It then ran on and printed, and that output was discarded (e). So a TERM trap in a hook's top-level shell does not run on cancel, but the shell survives long enough to write. For G2-3's writers this means an alert must be written by the code path that keeps running after the deadline (the late collector), not by a TERM trap. The probe did not measure how long a surviving hook may keep running.
3. **Group A's hook never runs**, as gap-G2 predicted, so `true` there costs nothing.
4. **The live fleet already registers FileChanged** (`~/.claude/hooks/file-changed.sh` on an absolute `~/.claude/file-watch-paths` arm plus a `*` dispatch, migration 0017). Its `*` group will also run once per alert event in every session (it is a logger). 0071 appends its two groups after it and leaves it unchanged.

## Cost (unchanged from gap-G2 §3)

One alert spawns the notifier in every live session (each exits unless the file is its own), plus 0017's logger. The writers (G2-3: #11's late collector, #8's sentinel) are not built yet, so until they land nothing writes to the alerts dir and the registration costs one idle watch per session.
