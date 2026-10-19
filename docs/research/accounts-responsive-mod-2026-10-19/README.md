# The /accounts readout on pane resize — a mod (2026-10-19)

Scope (frozen): the /accounts readout stays a clean, unwrapped layout when the pane is resized AFTER
it was drawn, at every width from 40 to 200 columns, in every session on all four accounts —
re-laying itself out for the new width (more columns when wider, fewer or stacked when narrower).
Proven by (1) a pty probe that draws /accounts at 160 columns, resizes to 40, and captures zero
wrapped grid rows, red on today's trunk and green after; (2) `claude plugin test` and
`claude plugin validate` on the mod; (3) tests/accounts-width-sweep.bats still 1..N, 0 not ok.
Landed and converged.

Operator, 2026-10-19, with a screenshot: "we break on small pane widths". A readout drawn while
the pane was ~157 columns was later viewed at ~35 and every grid row came out in two or three
pieces.

## Answer

Static text cannot do this; a `ui.render` hook can. `mods/accounts-readout` draws the readout
under its shell-command row from a width ladder `claude-accounts --readout` now leaves beside the
pane file, and Claude Code re-runs the hook at every width change. Measured on CC 2.1.293 in a
real pty, 160 → 40 columns, over the width-sweep fixture rows:

| arm | readout rows after the resize | intact | wrapped | wrapped grid rows |
|---|---|---|---|---|
| trunk (`hooks/relay-verbatim.sh` systemMessage) | 51 | 12 | 36 | **28** |
| mod | 45 | 41 | 0 | **0** |

`captures/out-trunk/`, `captures/out-mod/` hold the screens (`1-drawn-160`, `2-resized-40`, and
`3-redrawn-after-resize`: only what Claude Code drew after the resize) and `verdict.json`.

## Findings (probe first, then build)

1. **The site is `ToolGroup`.** The Bash row is folded into the group's `Ran 1 shell command` line,
   and a PostToolUse `systemMessage` is drawn under it (`⎿  PostToolUse:Bash says:`). The hook
   message is not a renderable component, so it cannot be restyled; it can only be replaced, by
   the mod drawing under the group and the hook drawing nothing. `ToolUse` holds the call when a
   group is unfolded (`--verbose`, ctrl+o); the mod hooks both. (`probe1-capture/render-log.txt`: the log of
   every `ui.render` call, and the probe mod.)
2. **Completed rows ARE redrawn on the normal (non-fullscreen) screen.** The probe's log shows
   `UserMessage`, `ToolGroup`, `AssistantMessage` and `TurnDuration` re-rendered at cols=40 and
   again at cols=100 after each resize, and the tree drawn at each width was the new one.
3. **…but only what is on screen.** A resize emits `ESC[2J` (clear the screen) and never `ESC[3J`
   (clear scrollback), then reprints as much of the transcript as fits. In the trunk run the
   reprint began mid-readout; with a 90-line reply after the readout (`captures/*-scroll/`) the
   readout was absent from the reprint in both arms. A copy that has scrolled away keeps the
   layout it was drawn with, and the terminal reflows it as it reflows any text.
4. **So the mod keeps the renderer's survive-one-split budget.** It draws, for each width, exactly
   the layout `_pane(cols)` draws (`pane_width`: half the pane, never under 44 cells, never over
   the pane), with that budget shipped in the ladder (`budget.cells[cols - from]`) rather than
   restated in TypeScript. Drawing the widest layout that fits instead (155 cells at 160 columns,
   tried first) would make a scrolled-away copy break after one split, which is worse than trunk.
   The rule is never worse than trunk: identical at the draw width, and re-laid out on screen at
   every later width, wider or narrower.
5. **Colour survives.** The pane render's palette is three SGR forms (reset, `38;2;r;g;b`,
   `1;38;2;r;g;b`); the mod turns them into `Text color="#rrggbb" bold` spans (467 truecolor
   sequences in the mod run's output).
6. **Cost: ~50-60 MB RSS per session that loads a mod** (304 → 352 MB and 289 → 350 MB, two
   pairs, a bare session after 12 s). That is why the launcher passes `--plugin-dir` on its own
   launches rather than exporting `CLAUDE_CODE_PLUGIN_DIRS`: an exported variable reaches every
   `claude -p` a session's shell starts, and none of those can draw anything.

## What was built

| part | where |
|---|---|
| width ladder: every layout from 35 to 195 cells, deduplicated, each with its widest line's cells, plus the `pane_width` budget per pane width 20-400; written to `<sid>.ladder.json` beside the pane file on every `--readout` in a session; `--ladder` prints it | `bin/claude-accounts` `pane_ladder`, `pane_ladder_file` |
| the mod: stamps `<sid>.mod` with the call's tool_use_id before the command runs, reads this run's ladder after it, keeps it in `$.state` (and the last 4 in `$.store`, for a resumed transcript), draws under `ToolGroup`/`ToolUse` | `mods/accounts-readout/` |
| the handshake: a stamp naming THIS call ⇒ the hook sends only its do-not-paste note, no static copy; no stamp or another call's ⇒ unchanged | `hooks/relay-verbatim.sh` |
| loading on all four accounts: install.sh links `mods/<name>/` into `~/.claude/mods/<name>/` (per-file, like skills); the launcher adds `--plugin-dir` for each live mod to every launch it makes (not `-p`, not a subcommand, not under `CC_MODS=off`) | `install.sh`, `scripts/deploy-link-parity.sh`, `lib/claude-launcher.zsh` |

Sessions already running when this converged keep the static copy until they are restarted;
nothing changes for them.

## Reproduce

```
bash docs/research/accounts-responsive-mod-2026-10-19/setup-probe.sh .          # TRUNK_REF=<pre-mod sha> for the red arm
/tmp/acct-probe/venv/bin/python docs/research/accounts-responsive-mod-2026-10-19/resize-probe.py trunk /tmp/acct-probe/trunk /tmp/acct-probe/out-trunk
/tmp/acct-probe/venv/bin/python docs/research/accounts-responsive-mod-2026-10-19/resize-probe.py mod "$PWD" /tmp/acct-probe/out-mod
```

Each run starts one Haiku session with `--setting-sources project` and its own `--settings`, so no
fleet hook runs and no shared settings file is touched; no slash command is typed.
