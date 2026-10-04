# bgjob-recycle — in-progress findings (2026-10-03, pre account switch)

- CC 2.1.284 bg primitives (claude --help): `--bg [prompt]` (prints short id), `--bg --resume <sid>`,
  `stop <id>` (conversation kept), `agents --json` (roster, no TTY), `attach <id>`, `logs <id>`,
  `respawn`, `rm`. In-session: `/stop` ends a bg worker; `/exit` in bg only DETACHES.
- bg worker env: CLAUDE_CODE_SESSION_KIND=bg, CLAUDE_BG_BACKEND=daemon, CLAUDE_JOB_DIR; KITTY_WINDOW_ID /
  ITERM_SESSION_ID stripped (dNe list). Spares inherit the DAEMON spawner's env (KITTY_PID, task list id).
- jobs/<short>/state.json: sessionId, resumeSessionId (current transcript sid; moves on /clear), cwd,
  respawnFlags (model/effort/permission-mode/settings/allowed-tools), name, bridgeSessionId (Remote Control),
  interactiveLineage=true for a session moved to bg from a TUI.
- No native successor link: fleet-view followId is UI focus only; agents-view reply (`job_reply`) has no CLI.
- ROOT CAUSE of 032aa97f: handoffs.jsonl 02:30:34Z `recycle-bgwork-answered` — self-recycle /exit raised the
  background-work dialog (live bg task: `pnpm review:bottles --port=3334`, started 02:15:49), watcher answered
  '2' Move to background and exit → conversation forked into bg job 032aa97f (with the Remote Control bridge,
  so the operator's remote view followed the COPY). Relaunch in pane 168 then STALE:boot (no claude in 181s).
  Self-recycle path never censuses its own bg tasks (hf_bg_work_gate only on remote/at-rest path; selfcall
  retry W7c only for the NO-keep-work menu shape). C5 §E2 had measured this class (18 slash forks) as a hazard.
- Operator then /clear'ed the bg job by hand at 02:46 (transcript 47c6b9d3) — /clear in a bg job keeps the
  job id and the bridge, i.e. the in-place shape the operator expects.

## REPRODUCED 2026-10-04T04:12:21Z on the cc-lr switch next3→next4 (pane 198, watcher pid 2672)
- The SWITCH path hits the same defect: handoffs.jsonl `recycle-bgwork-answered` 04:12:21Z, "the /exit raised the
  background-work dialog at 15s; answered '2' (Move to background and exit)". So `cc-lr switch` rides __recycle
  and the fix must cover it, not only `handoff-fire.sh --recycle`.
- Result: TWO live copies. (a) pane 198, next4, resumed 42097363, new bridge cse_01KNaZ3Enmsgtq1TqXvtaEXk,
  engaged 04:17:32Z — the sanctioned successor, it continues. (b) accidental bg fork job 56c02192 on next3
  (~/.claude-tertiary/jobs/56c02192, sid 56c02192-60af-…, bridge cse_019v7kriq4wa3T13NUyETYrU,
  interactiveLineage=true). The fork stood itself down with `claude stop 56c02192` (conversation kept;
  `claude rm` it once no longer useful as evidence). It has no sanctioned rail to retire: --recycle refuses
  a bg session at scripts/handoff-fire.sh:12668 (hf_bg_recycle_refusal).
