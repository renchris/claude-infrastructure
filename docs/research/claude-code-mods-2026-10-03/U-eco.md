# U-eco: Claude Code mods ecosystem scan (2026-10-03, two days after launch)

Tags: **M** = I checked it here (method named). **R** = a third party reported it (cited, not reproduced). **I** = my inference. Raw pulls are in `/tmp/mods-research/eco/`.

## (a) Existing mods

| Mod(s) | Source | What it does | Maturity |
|---|---|---|---|
| agents-md, diff, sec-default, telemetry | github.com/anthropics/claude-code/tree/main/mods | AGENTS.md loading; `/diff` pane; guard for org policy; first-party analytics | Built into the binary, with tests. **M**: `gh api git/trees/main?recursive=1` lists 1,749 entries under mods/, 1,117 of them diff's |
| plugin-authoring (a skill with no code), you-should-know (side agent, off by default) | code.claude.com/docs/en/plugins/mods/overview | Built-ins with no public source | **M**: fetched the docs page |
| token-weather, blast-radius, replay-theater | github.com/anthropics/claude-code-playground/tree/main/claude-code/mods | Context forecast band; holds a risky Bash command with a dry run; steps through the last turn's edits | Samples "shared as-is, no support". **M**: repo created 2026-09-25, 91★, 1 open issue |
| Community catalogue | github.com/karanb192/awesome-claude-code-mods (mods.aidojo.si) | Runs `claude plugin validate` over GitHub mods and records each one's reach | **R**: says "1020 mods · Last scanned 2026-10-03" (awesome.md:11) |

Community maturity, **M** (`gh api repos/...` on 25 repos that overlap the fleet): most were created between 2026-10-01 and 10-03. The top star counts are lcm with 41★ (it predates mods), karanb192/claude-code-mods with 34★ and ContextSaver with 25★ (304 tests). Most have 0–8★. Treat all of them as prototypes.

Discussion: Hacker News launch posts got 1–6 points and 0 comments (**M**, hn.algolia `search_by_date`). Reddit refused the request (403). The only substantive outside analysis is a Pluto Security post (pluto.security/blog/claude-code-function-hooks-security, 2026-09-22). Most of what is known is in design thread anthropics/claude-code#91870 (242 comments, `eco/i91870-comments.md`).

## (b) Most useful patterns and gotchas

1. **A deny only blocks if it comes before `next`.** Returning `{deny}` after `await next(e)` does not stop the tool. **R** gbrussich52 on #91870 (2026-10-03): the file was written in 3 of 3 runs while the model was told the write failed.
2. **Failures let the call through.** A hook that throws, or returns the wrong shape, is skipped and the tool runs anyway (**R** 42tahara, fragmentsstudio on #91870). A `.catch` that returns `{deny}` does block, 3 of 3 runs (**R** gbrussich52). Any guard must wrap its body that way.
3. **Holds have no headless path.** In `claude -p`, blast-radius polls for 10 minutes and then refuses, even for a command that would delete nothing. **R** claude-code-playground#2 (2.1.288, 611 s of wall time). **M**: none of the three samples checks `isInteractive` (grep). Any mod that asks the user needs a fallback for unattended runs.
4. **Hot-reload state.** The guide says to keep data in `$.state`, because module variables reset on reload. **M**: all three playground samples use module variables anyway: `token-weather.mjs:30 let readings = []`, `blast-radius.mjs:24`, `replay-theater.mjs:16`. Hot reload works for `--plugin-dir`. For installed mods, "`/reload-plugins` does not reload it" (**R** nateherkai README). A user-level mod kept serving old code for three runs while `-p` loaded the new code fresh (**R** lperezmo, #91870).
5. **One mod per AbovePrompt band.** When two mods draw there, only one shows. Blast-radius's buttons can disappear, and the held command is then refused after 10 minutes. **M**: playground READMEs blast-radius:118, token-weather:118, replay-theater:121. Return `next(e)` when there is nothing to draw.
6. **Limits:**
   - 10 s of a hook's own time per dispatch; waits inside `$` calls don't count (blog).
   - Text over 10,000 characters, or a tree over 100,000, blanks the whole site (**R** xuanji86).
   - A module can link at most 512 files (**R** konsta95, 2.1.278).
   - `session.end` gets 1.5 s by default (**R** ajwillia; `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` raises it).
   - Hooks run strictly in series, about 3 ms of host overhead per link; 25 pass-through hooks add 5 ms (**R** deafsquad).
7. **Large modules load late.** A diff-sized module is evaluated 3–4.4 s after start while the prompt is live at 1.7 s. A command typed in that gap goes to the built-in (**R** konsta95). Keep modules small.
8. **Use literal matchers on `tool.call`.** A hook without one hops to the worker thread. On 2.1.287 that broke worktree-isolated subagents. **R** Und3rf10w; fixed in 2.1.288 (**M** CHANGELOG.md#L57). A literal matcher like `{tool:"Bash"}` is tested on the main thread.
9. **Usage figures.** `context.percent` is a share of the full window, not of the auto-compact point. In testing the band read 81% while the built-in notice read 90% (**M** token-weather README:113). After Esc, `usage()` has no token count until the next response (**R** konsta95).
10. **Rollout switch.** Mods are "on by default", but GrowthBook can turn them off: "the rollout switch served off". **R** anthropics/claude-code#99130 (open, 2.1.288) and simon-bauer on #91870. Check with `claude plugin test`.
11. **Security.**
    - `$.fs`, `$.process` and `$.http` reach anything the user can, and nothing is disclosed at install (**R** Pluto; secondarykey on #91870).
    - sec-default only loads on managed or Team/Enterprise machines (**M** sec-default/README.md:178-188). **I**: on Max accounts without managed settings, a user mod can therefore return allow over a deny rule on `tool.check` (README:114-117).
12. **Transcript path.** `$` has no transcript path, so archivers rebuild `$HOME/.claude/projects/<slug>/<id>.jsonl` (**R** ajwillia). **I**: that path is wrong under `CLAUDE_CONFIG_DIR`.
13. **Teammates.**
    - Up to 2.1.288: `agent.spawn` did not fire for teammates, agent ids did not match across events, and idle teammates still showed "running" (**R** tzafrir). Fixed in 2.1.289 (**M** CHANGELOG#L21).
    - `tool.check` carries no `agentId` (**R** scasella).
14. **Other.** `/diff` holds other mods' toasts (#99026). Naming `hooks` in plugin.json kills the load silently (**R** fragmentsstudio).

## (c) Bugs and regressions in 2.1.287–2.1.289 that matter for adopting mods

| Ver | Item | Status |
|---|---|---|
| 287 | A `tool.call` hook breaks worktree-isolated subagents (#92533) | Fixed in 288 (CHANGELOG#L57) |
| 287–288 | Rollout switch serves mods off (#99130). Stale cache made `plugin test` misreport | Open; the misreport is fixed in 288 (#L123) |
| ≤288 | Installed mods don't load in the first session after an upgrade | Fixed in 289 (#L11) |
| ≤288 | Supervised and background sessions end when a plugin's on-screen handler throws asynchronously | Fixed in 289 (#L16). 288 also fixed sessions ending on reload while timers ran (#L60), and an "unrecoverable interface error" with band rows plus the background-tasks dialog (#L63) |
| ≤288 | A mod's approval could lift a deny rule on a nested part of a compound command, on managed machines | Fixed in 289 (#L5) |
| 288 (not mod-specific) | The new inline-shell `rm` check asks on `zsh -c` and `bash -c $'…'` scripts that contain no `rm`, even in bypass mode. No permission rule can approve it, and unattended sessions deny it after the timeout (#99249, #99320) | Open |
| 287 / 288 | Fullscreen: scroll acceleration and broken text selection (#99004); the saved `tui: fullscreen` setting is not applied to new sessions (#99284). Panes dock only in fullscreen | Open |
| 289 | A skill's allowed-tools grant is lost to a race; it held in 3 of 28 runs (#99353) | Open |
| 280+ | Hooked `PromptHint` draws one stacked frame, a flicker (**R** konsta95) | No fix found in the changelog (**I**). An issue search for "flicker" found nothing else from 287–289 (**M**) |

**The fleet's pinned 2.1.284.**
- **M**: the binary contains `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS` (13 hits), `tengu_plugin_hooks_modules`, and "Function hooks should only be used in REPL context" (`grep -a -o` on `~/.claude-284/.../claude.exe`).
- **M**: four config dirs cache `"tengu_plugin_hooks_modules": false`: `.claude-next`, `-secondary`, `-tertiary` and `-quaternary` `/.claude.json` (grep).
- **R**: on 2.1.283/284, setting the env flag in settings.json enables mods (iritbrener-blip, #91870).
- **I**: 2.1.284 runs the pre-GA API and lacks every fix above. Adopting mods safely for unattended panes means unpinning to at least 2.1.289.

## (d) Overlap with this fleet's needs

**Context, quota and cost meters**
- token-weather (official sample).
- context-view (kongyo2).
- context-lens, quota-meter and token-ledger (Arunjay4213/claude-mods).
- cctop.
- usage-band (pawandeepdhall).
- **twin-meter** (abhibansal60/claude-mods): 5h/7d limits for two cswap accounts. It is the closest match to the 4-account setup and gets its data from Bash calls.
- **spare10** (chrisns/spare10-mod): at a quota reserve it holds all work.
- **cache-keeper** (nateherkai): cache warm/cold state, a guard before cold sends, a `/board` of every local chat, and `/handoff`.

**Session-state export and handoff**
- **compact-keeper** (arasovic): writes each compaction summary to `~/.claude/handoffs`.
- auto-handoff (promptadvisers).
- **ctx-handoff** (cablate): automatic handoff plus `/clear` at a context threshold.
- compact-handoff (AnExiledDev).
- session-saver `/park` (hamzafer).
- spike-handoff (ucsandman): writes a bundle at `turn.complete`.
- A transcript uploader that hooks `turn.complete`, `session.compact` and `session.end` worked in `-p` on 2.1.275 (**R** ajwillia; repo not named).

**Safety guards**
- blast-radius.
- launch-codes, merge-gate and scope-guard.
- **kb-settings-guard** (ray-manaloto): denies a delegated agent any write to Claude settings files.
- claude-doctor: refuses tool calls while the install is broken.
- secret redactors: secret-redactor, secret-mask, honmoon.
- **Collision Guard** (nateherkai): asks before editing a file another open chat changed in the last 30 minutes.
- leftovers (homieyangg): a ledger of processes left running.
- drift-fuse: scores unattended turns.

**Multi-session and agent dashboards**
- flightdeck.
- agentpane.
- agent-flow.
- whats-agent-doing.
- **notice-board** (HolyGrail): notices to every session in a repo or on the machine.
- **AFKSwitch**: broadcasts presence to live local sessions.

**Caveats**
- Panes, bands and status rows do not draw in `claude -p` or the Agent SDK; only the hooks run (**M** docs table, "Where mods run").
- **I**: none of these mods was checked for `CLAUDE_CONFIG_DIR` awareness. twin-meter is specific to cswap.
