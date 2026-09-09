# A12 — SKEPTIC pass 2 on `A12-upstream-features.md`

Wave: exhaustive-drive 2026-09-08. Read-only. Second skeptic; the first pass is
`A12-upstream-features.skeptic.md` (17:58). This pass re-ran the axis's numbers independently, checked the
first skeptic's own new claims, and then hunted what BOTH missed. "measured" = I ran it; everything else is
labelled inferred. Scratch extract of the 2.1.260 binary: `tr -c '[:print:]\n'` + `awk 'length>=30'` ⇒
142,065 lines / 41,127,320 bytes (matches the axis's 142,065). `timeout` is not on this machine's PATH;
bounds were `perl -e 'alarm N; exec @ARGV'`.

## Headline: R1 is refuted, and the refutation is a repo fact both passes missed

`ENABLE_STOP_REVIEW` is not a Claude Code binary variable and never was — the axis and skeptic 1 are right
about that — but it is **not inert and not cargo**. It is the Stop-review gate of Anthropic's
`security-guidance` plugin, installed machine-wide, and the `=0` was set deliberately with a written reason:

- `~/.claude/autonomy/backlog.jsonl` row `022683ab85f3` (measured, three events): 2026-07-29 `add`
  "install security-guidance plugin machine-wide (ENABLE_STOP_REVIEW=0; keep ANTHROPIC_API_KEY unset or it
  bills at-cost per turn)"; `block` "/plugin install security-guidance@claude-plugins-official, then set
  ENABLE_STOP_REVIEW=0 (**multi-agent worktrees break its Stop-hook diff review**)"; `done` 17:57Z
  "installed to all 4 config dirs … ENABLE_STOP_REVIEW=0 set in … settings.json env block". DoD ref:
  `docs/research/codex-security-in-claude-code-2026-07-29.md` (present, 15,637 B).
- Consumer (measured): `~/.claude/plugins/cache/claude-plugins-official/security-guidance/2.0.7/hooks/security_reminder_hook.py:162`
  `ENABLE_STOP_REVIEW = os.environ.get("ENABLE_STOP_REVIEW", "1") != "0"` and `:1910-1913`
  `if not ENABLE_STOP_REVIEW: debug_log("Stop hook: ENABLE_STOP_REVIEW=0"); _skip(50)`. Same in 2.0.6.
- The plugin registers a **Stop hook** (`hooks/hooks.json`: SessionStart, UserPromptSubmit, PostToolUse ×6,
  **Stop ×1, no `timeout` field** ⇒ the 600 s command default) plus `installed_plugins.json` says
  `security-guidance@claude-plugins-official 2.0.7, scope user, lastUpdated 2026-09-08T18:28:37Z`.
- It ran here: `~/.claude/security/log.txt` (one file, the other three `security/` dirs symlink to it)
  holds **10** lines `Stop hook: ENABLE_STOP_REVIEW=0`, last at 2026-07-30 01:45:46 (measured
  `grep -c`). Nothing has been written to that log since 2026-07-30 04:09 and `debug_log` is ungated
  (`_base.py:56-75`), so the plugin's hooks are currently **dormant** (not in `enabledPlugins` in any of the
  four settings files) — but the cache was refreshed today and the row that installed it is `done`.

Why this refutes R1 rather than merely annotating it: the axis's fail-direction line reads "Neither — the
variable is inert, so removal cannot break anything." Removal re-arms an LLM git-diff review on **every
Stop**, at a 600 s default timeout, the moment the plugin is enabled again — with no trace pointing at the
deleted line. That is the silent-in-the-dangerous-state shape, on the exact surface (Stop latency) this
wave is about. The correct action is the opposite of R1: keep the line and put the reason beside it (the
env block cannot carry comments, so the record is the backlog row and the 07-29 doc — both already exist).

Method note for the house: three passes grepped a **binary** for an **env var** and read 0 as "never
existed". An env var's consumer set is `binary ∪ hooks ∪ plugins ∪ shell`; skeptic 1 covered hooks/scripts/
bin/commands/skills/zshrc and stopped one directory short (`~/.claude/plugins`). The cheapest instrument
was the backlog store: `grep STOP_REVIEW ~/.claude/autonomy/backlog.jsonl` — one line, answers it.

## 1. Numbers re-checked (measured unless marked)

| claim | axis | this pass | holds |
|---|---|---|---|
| registered hooks | 105 / 21 events / 100% command | `python3` census of `~/.claude/settings.json` (mtime 16:23): **100** hooks / 21 events / {command}; one `asyncRewake` (SessionStart mailbox-wake-arm); 0 `if`/`once`/`model`. Other accounts **94 / 95 / 94** hooks, **20** events, Stop = 12 in all four | types yes; count no; "fleet-identical" no |
| `ENABLE_STOP_REVIEW` in 219/220/260 | 0/0/0 | `LC_ALL=C /usr/bin/grep -a -c -F` ⇒ **0/0/0**; `STOP_REVIEW`/`stopReview`/`stop_review` 0 in 260 | number yes; **conclusion no** (§ headline) |
| positive controls in 260 (`grep -a -o \| wc -l`) | AWAY 4, PROMPT_SUGGESTION 7, TODO 3, DEPTH 5 | AWAY **4**, PROMPT_SUGGESTION **9**, TODO **4**, STOP_HOOK_BLOCK_CAP **5** (`-o` counts occurrences, axis's `-c` counted lines) | yes |
| cap code | `Vd=env??8; if(Vd>0&&qd>Vd)` @16480451 | verbatim at **@16480439**: `let Vd=a.CLAUDE_CODE_STOP_HOOK_BLOCK_CAP??8;if(Vd>0&&qd>Vd)return i("tengu_stop_hook_block_count",{…hit_cap:!0,goal_active:zf}),yield kt(\`A hook blocked the turn from ending ${qd} consecutive times…\`,"warning")…{reason:"completed"}` | yes |
| genuine cap hits, 30 d | 6 events / 4 files of 6,140 | `find` (4 realpath'd roots, `-mtime -30`) ⇒ **6,216** files; positive control `'assistant'` **5,977**; raw string 147 lines / 53 files; **`type:"system"` events 4 in 3 files** (08-10 ×2, 08-19, 08-26, all "9 consecutive"); the 18 unparsable raw lines were all our own research prose quoting the message. Difference from the axis = two 08-09/08-10 events aged past the 30-d edge between runs | yes in magnitude |
| agent hook: `dontAsk`, fails open | as stated | `toolPermissionContext:{…mode:"dontAsk"…}`; `tn>=50 ⇒ abort`; both `!on` paths return `{hook:e,outcome:"cancelled"}` @17531578; `NUe(): if(e==="dontAsk")return"deny"` @8795763 | yes |
| agent hook default 60 s, Haiku | stated, skeptic 1 could not locate | `let ye=e.timeout?e.timeout*1000:60000` @17528944; schema `timeout … (default 60)`, `model … If not specified, uses Haiku` @8905328 | yes |
| allowlist: only 5 judge-relevant rules | cat/git log/git status/jq/Read | user layer 339 rules; the axis's filter missed **`Bash(python3:*)`** (a universal Bash escape hatch — `python3 -c 'subprocess.run([...])'` runs anything) and `Grep`; **project layer** `.claude/settings.json` (35 rules) carries `Bash(cc-backlog:*)`, `Bash(bin/cc-backlog:*)`, `Bash(cc-decide:*)`, `Bash(scripts/wrap-ledger.sh:*)`, `Bash(bash scripts/wrap-ledger.sh:*)`; `settings.local.json` (95) adds `Bash(python3 -)`, `Bash(bin/cc-backlog)` | **premise fails** |
| `"name":"ProposeGoal"` / `ProposeGoal` in 219, 220 | 0 files; 0/0 | `ProposeGoal` 0/0 in 219/220, **18** occurrences in 260 (`-o`) ; `isEnabled(){…if(!mct())return!1…}` @27060364; `function mct(){return I("tengu_propose_goal",!1)}` @24137396 | yes |
| override spellings | 0 each | STATSIG_LOCAL_OVERRIDE / gateOverride / statsigOverride / forcedGates / overrideGates / CLAUDE_CODE_FLAGS / localOverride ⇒ **0** each; regex `[Oo]verride[A-Za-z]*[Gg]ate\|…\|GATE_OVERRIDE` ⇒ 0 | yes |
| flag observable locally? (skeptic 1: GrowthBook cache) | axis: no | **Five** `.claude.json` files, not four: `$HOME/.claude.json` (556 GB keys, stamped **2026-08-11** — STALE) and `<config-dir>/.claude.json` ×4 (442 / 610 / 610 / 610 keys; three stamped **2026-09-08 23:xxZ**). `tengu_propose_goal` **absent in all five**; `tengu_rosy_wren` absent in all five; `tengu_saffron_wren` true ×4; `tengu_hushed_lark` 5 ×4; `tengu_umber_kestrel` F/F/T/F/T | skeptic 1 confirmed, with a correction: read the config-dir copy, not `$HOME/.claude.json` |
| `/goal` is a prompt Stop hook | `KEe()` | `o.sessionHooksRegistry.add(r,"Stop","",{type:"prompt",prompt:t})` @11566244 | yes |
| ScheduleWakeup guidance text | quoted | verbatim @11653684 | yes |
| Stop payload `background_tasks` / `session_crons` | schema | both `.optional()`, descriptions verbatim @9987710 | yes |
| readers of `background_tasks` in repo | only goal-inert-watch.sh | `grep -rl` hooks/ bin/ scripts/: **goal-inert-watch.sh, subagent-stop.sh, validate-bash.sh** (comment); `session_crons`: **subagent-stop.sh, goal-inert-watch.sh** (axis: "nothing"); `last_assistant_message`: subagent-stop.sh, stop-failure-marker.sh | no |
| `SubagentStop` registered | 0 | 0 in all four settings; `migrations/0014-subagent-stop-registration.sh` (`# migration-class: c10`) staged at `~/.claude/autonomy/migrations/staged/0014-….json`; rows 7ea31ffa1a08 / 2cc7ee852288 / 56db7fb21284 `done`, 296cc04bc3fd `block` | yes, but see R2 |
| IDL: 0 task-* records, session-continue 682 | as stated | Counter over `hook` field: `?` (no `hook` key) **36,616**, waiting-recycle 13,966, session-continue 826, goal-inert-watch 597, dispatch-assert 562, anti-deference 558, completion-assert 531, operator-readout 412; **subagent-stop 0**; task-* 0 | yes (counts moved; IDL is live) |

## 2. Recommendation verdicts (axis → this pass)

- **R1 delete `ENABLE_STOP_REVIEW` (96 %) → REFUTED, 15 %.** Consumer exists, deliberately gated, row
  `022683ab85f3` done, plugin installed and cache refreshed today. Deleting errs **silent-in-the-dangerous
  state** (a 600 s-default LLM Stop review re-arms with no pointer to the cause). Surviving action: none on
  settings; if anything, add the row id to the migrations README's "env lines with a reason" list.
- **R2 register SubagentStop, advisory `exit 0 + additionalContext` (88 %) → REFUTED as written, 30 %.**
  Already staged as migration 0014 (C10, blocked row 296cc04bc3fd). The prescribed `additionalContext`
  contradicts the hook's test-pinned contract (`hooks/subagent-stop.sh:39-41`: on SubagentStop it "extends
  the turn and increments the harness's consecutive-block counter … writes NOTHING to stdout"). Errs
  **nagging** (a subagent forced into extra turns — the documented loop incident). Surviving action: the
  operator runs 0014, which is already in the `cc-do` pile.
- **R3 do not adopt an agent Stop hook; land allowlist first (84 %) → direction holds, premise fails; 78 %
  for "not now".** Fail-open (`cancelled`) and `dontAsk ⇒ deny` are verbatim, so "not as-is" stands. But the
  allowlist step is already done at the project layer for this repo, and the user layer's
  `Bash(python3:*)` means the judge is never actually *denied* a path to the evidence — the real limit is
  that a Haiku judge would not find it unprompted. Also: the trial's instrument (`tengu_agent_stop_hook_*`)
  is remote telemetry; the local signal is `--debug`'s `Hooks: Agent hook …` lines only. 0 genuine
  agent-hook emissions in 6,216 transcripts — every cost figure is code-derived (the 126,630-byte schema is
  the *session's* largest tool-definition line, inferred to be the judge's payload).
- **R4 leave cap at 8, never 0 (93 %) → HOLDS, 90 %.** Code verbatim; census reproduces in magnitude.
  Confound (skeptic 1's, confirmed): our own chain self-caps first (`CLAUDE_CONTINUE_MAX`), so "6 hits"
  measures our bound. Also: **none of the 11 blocking-capable Stop hooks in settings reads
  `stop_hook_active`** (`grep -c stop_hook_active` = 0 for session-continue, anti-deference, completion-
  assert, dispatch-assert, boundary-handoff, operator-readout, goal-inert-watch), which is exactly the
  field the binary's own cap message tells hook authors to check. Non-action, direction correct.
- **R5 read `background_tasks`/`session_crons` as the D8 discriminator (90 %) → REFUTED as a substitute,
  40 %.** `goal-inert-watch.sh:50-67` documents the field as a backgrounded-only view — an empty list is
  not "idle". Errs **silent-in-the-dangerous-state** (foreground gate mid-run rendered as idle). Salvage:
  one honest ledger bit — a cron/backgrounded task WILL wake this session — read in a Stop hook, never in
  `/wrap`, never as a block.
- **R6 file `tengu_propose_goal` as `not-yet-true` + falsifier (92 %) → HOLDS, 88 %, falsifier
  corrected.** Use the config-dir cache, not `$HOME/.claude.json` (stale since 08-11):
  `jq '.cachedGrowthBookFeatures.tengu_propose_goal' ~/.claude-tertiary/.claude.json` ⇒ `null` today.
  Errs toward waiting on a remote flag; self-retracting.
- **R7 import ScheduleWakeup guidance (87 %) → REFUTED, 25 %.** `CLAUDE.md:162` and `commands/handoff.md:616`
  already carry the event-driven rule; ScheduleWakeup is `/loop`-bound and used 17× in 30 d; resident
  policy restating a perishable product fact is a named memory rule. Errs toward resident-context padding.
- **R8 no declared prompt Stop hook while /goal stands (89 %) → HOLDS, 88 %.** `KEe()` verbatim; shared
  per-turn counter verbatim. Non-action.

## 3. What the axis (and skeptic 1) missed that the question required

1. **Plugin hooks are a hook surface the settings census cannot see.** `security-guidance` registers a Stop
   hook with no timeout (600 s default) — a potential 13th Stop hook invisible to A01's timing and A12's
   census; dormant since 07-30 by its own log, but installed and refreshed today. Any "our Stop chain is
   12 hooks" statement should say "12 in settings + N plugin".
2. **`ENABLE_STOP_REVIEW` consumer + its backlog row + its doc** (§ headline).
3. **`Bash(python3:*)` in the user allowlist** — turns the "judge denied its evidence" argument into "judge
   not told where its evidence is"; also a fact A05 (permission loop) should own: a `dontAsk` judge with
   `python3:*` has unbounded Bash reach.
4. **`stop_hook_active` is read by 0 of our 11 blocking-capable Stop hooks** while the harness's cap text
   names it as the fix — the cap census cannot distinguish "no pressure" from "we never yield to the
   harness's own back-pressure signal".
5. **`continue:false` audit**: only `teammate-auto-shutdown.sh` (TeammateIdle, line 1238) emits it; no
   Stop-family hook does — so the `stop_hook_prevented` dead-stop path is not a live hazard today. Worth
   stating, since it is the one hook output that ends a session outright.
6. **Five `.claude.json` stores, one stale.** `$HOME/.claude.json` last refreshed 2026-08-11; any flag
   read must use the config-dir copy (memory rule: "one dir ≠ installed").
7. **Store read times.** 105→100 hooks and 6→4 cap events are both live-store drift within hours; a number
   from a live store needs its read time next to it.

## Provenance

Settings census: `python3 -c "import json;…"` per `~/.claude*/settings.json`. Binary: `LC_ALL=C
/usr/bin/grep -a -c|-o -F` on the three `.exe`s; contexts via `re.finditer` over the extract. Corpus:
`find <4 realpath'd roots> -name '*.jsonl' -mtime -30 | sort -u` (6,216) → `xargs -P 8 -n 200 /usr/bin/grep
-H -F` → Python `type=="system"` filter (stderr captured to files, 0 lines). Plugin: `~/.claude/plugins/
installed_plugins.json`, `cache/…/2.0.7/hooks/{hooks.json,security_reminder_hook.py,_base.py}`,
`~/.claude/security/log.txt`. Backlog: direct `json.loads` over `~/.claude/autonomy/backlog.jsonl`.
