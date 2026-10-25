# S04 — CC 2.1.293 interrupt / resume semantics: what an interrupt-then-resume move loses

Slot: S04-cc-interrupt-resume-semantics · 2026-10-25 · read-only research.
Source: `/tmp/mtam/cc293-src.js` (52,710,919 bytes, extracted CC 2.1.293). Offsets below are byte
offsets into that file (all measured with the helper scripts below). Docs: code.claude.com (the
docs.claude.com URLs 301 to code.claude.com/docs/en/...).

## Method

Helper scripts (scratch, not deliverables) in `/tmp/mtam/S04-cc-interrupt-resume-semantics/`:
- `g.py PATTERN [ctx] [max]` — regex over the file, skipping the binary prefix below offset 2,000,000.
- `at.py OFFSET [before] [after]` — print a window.
- `rng.py PATTERN LO HI` — regex inside a byte range.
- `cl.py` — extracts the embedded changelog string (function `kMr`, bytes 19,042,469–19,129,588,
  versions 2.1.286–2.1.292) to `changelog.txt` (614 lines).
Every command was wrapped in `timeout 60`. No claude process launched, no pane touched, no
credential read. One filesystem listing of `~/.claude*/{sessions,projects}` (ls -ld only).

Docs fetched (WebFetch): code.claude.com/docs/en/interactive-mode, /checkpointing, /sessions,
/prompt-caching, /agent-view (two pages of it), /env-vars (two pages), /authentication, /hooks
(first 100k chars only).

Note: minified names collide across chunks (e.g. `pL` is a constant in one chunk and a function
in others). Every identifier claim below was checked in its own chunk context.

---

## (1) What Esc / interrupt writes mid-tool-loop, and how --resume repairs a dangling tool_use

### Marker constants (chunk at ~2,677,000)
@2677211:
- `ow="[Request interrupted by user]"`
- `Au="[Request interrupted by user for tool use]"`
- `PT="[Tool call did not complete: the turn was ended to deliver the message that follows. Nothing refused it; re-run it if still needed.]"`
- `pL="[Tool call interrupted: the session ended before this call's result was recorded, so its outcome is unknown. Check whether it took effect before relying on it or running it again.]"`
- `fL="[Tool call result not in this copy: this session was copied from another session before that session recorded this call's result. ...]"`
- `uv="The user doesn't want to take this action right now. STOP what you are doing and wait for the user to tell you how to proceed."`
- @2680369 `sit="User rejected tool use"`, `mx="API Error: Request was aborted."`

### Abort reasons
@3899241–3900515: AbortError reasons `user-cancel`, `remote-cancel`, `shutdown`, `interrupt`,
`turn-abort`, plus `refusal-fallback-edit`, `permission-stop`, `background`, `subagent-park`.
`IT(signal)` returns `true` only when the reason is `shutdown` → sets `interruptedByShutdown`.
`gce(reason)` is true for `interrupt|turn-abort|refusal-fallback-edit|permission-stop`.

The interactive REPL's Esc uses `user-cancel` (remote viewer uses `remote-cancel`):
@33413021 `let yt=h==="remote"?"remote-cancel":"user-cancel"; ... Ne?.abort(cc(yt))`.
"Send now" (Ctrl+Enter / queued message) uses `interrupt` (@33403976) and `turn-abort` (@33428344).

### What lands in the transcript on Esc mid-tool-loop
1. Per in-flight / queued tool in the streaming tool executor, `createSyntheticErrorMessage`
   @18063521 (reason `user_interrupted`):
   - abort reason `turn-abort` → tool_result `content:PT, is_error:true, toolDenialKind:"interrupted"`.
   - reason `background` → `cj(uv)`, `toolDenialKind:"cancelled"`.
   - otherwise (Esc = `user-cancel`) → tool_result `content:cj(Ow)` (a `<tool_use_error>`-wrapped
     rejection text; `Ow` is a chunk-local alias I did not resolve), `toolUseResult:sit`
     ("User rejected tool use"), `toolDenialKind:"user-rejected"`,
     `interruptedByShutdown:IT(signal)`.
   - A tool whose own call threw on the abort gets `<tool_use_error>Error calling tool...` with
     `toolDenialKind:a3t(...)` = `"interrupted"` (or `"cancelled"` for background) @11950321 / @11936053.
2. Then the query loop's abort path @18200820 (`reason:"aborted_tools"`):
   `if(!gce(reason)) yield CR({toolUse:!0, interruptedMessageId:Nn(f), interruptedByShutdown:IT(...)})`
   → a user text message `"[Request interrupted by user for tool use]"` (CR @14010954:
   `text:e?Au:ow`). Aborts during streaming without tools write `"[Request interrupted by user]"`
   (@18135396, @18155445, @18186871, `reason:"aborted_streaming"`). `interruptedMessageId` is the
   msg_* id Esc cancelled, only for user-cancel/remote-cancel (`Nn` @18133948; schema @2988381).
   For `interrupt`/`turn-abort` (send-now) NO "[Request interrupted…]" marker is written.
3. Detached tool calls (a tool that detached from the turn) are stopped with `user-cancel` by
   `stopRunning()` @11592499 and settle as "The user stopped this call before it finished." @11899925.
Docs (interactive-mode): "`Esc` | Interrupt Claude ... Stop the current response or tool call
mid-turn so you can redirect. Claude keeps the work done so far." and for Ctrl+Enter: "Running
shell commands, subagents, or other work that can move to the background: that work moves to the
background and keeps running" (https://code.claude.com/docs/en/interactive-mode).

### How resume repairs dangling tool_use (deserializeMessages, `tLt` @10985000–10990700)
- @10985xxx `let M=g??a.CLAUDE_CODE_RESUME_INTERRUPTED_TURN, G=Np(), q=!G?Au:h?fL:pL;`
  `Np()` (@4126254) = feature flag `tengu_foamy_spring`, default true. So the synthetic result text
  is `pL` ("session ended before this call's result was recorded…"), `fL` for a fork copy, or the
  legacy `Au` if the flag is off.
- Trailing unresolved tool_use ids are collected (`outTrailingUnresolvedToolUseIds`), then
  `HDt` @10990952 appends, per dangling tool_use, a user message
  `{type:"tool_result", content:q, is_error:true, tool_use_id}` with `toolDenialKind:"interrupted"`.
- If the tail classifies as `interrupted_turn`, a meta user message `"Continue from where you left
  off."` (`$Sn()` = `CLAUDE_CODE_RESUME_PROMPT` or default, @10984xxx) is pushed only when `M`
  (env set) or `!G`; otherwise it is deferred (`yo=!0`). A trailing user row gets an assistant
  sentinel `"No response requested."` (`yF` @2915094) spliced after it.
- Tail classification `cmo` @10991xxx: a last user row that IS an interrupt marker (`WDt`: text ===
  ow or Au) yields `interrupted_turn` ONLY if `interruptedByShutdown` (`jDt` @10994207); a plain Esc
  marker yields `{kind:"none"}` — nothing to continue.
- Stale bounds: `CLAUDE_CODE_RESUME_INTERRUPTED_TURN_MAX_AGE_MS` (`ZDt`), and a flag/default bound
  `eLt`: default 21,600,000 ms = 6 h (`emo`), flag `tengu_shimmering_cherny` range 60 s–30 d.
- Interactive REPL restore @18279143: auto-submits the continuation ONLY
  `if(a.CLAUDE_CODE_RESUME_INTERRUPTED_TURN && turnInterruptionState.kind==="interrupted_prompt" && qy(origin))`
  (log text "Auto-resuming interrupted turn for bg crash-respawn"); `qy` @4109951 accepts origin
  undefined/human/auto-continuation. Without the env the resumed session starts idle.
- API-send-time safety net `Ron` = ensureToolResultPairing @14142772–14146900: missing results get
  `"[Tool result missing due to internal error]"` (`PUr` @13994290), orphan tool_results are removed
  (`"[Orphaned tool result removed due to conversation resume]"`), duplicate tool_use ids are
  dropped (`"[Tool use removed]"` / `"[Tool use interrupted]"`), event
  `tengu_tool_result_pairing_repaired`; strict mode (`getStrictToolResultPairing`) throws instead.
- Docs (sessions, "What a resumed session restores"): "Interrupted tool calls: a tool that was
  still running when the previous process ended ... doesn't finish or get rerun when you resume.
  Claude sees the call marked as cut off before its result was recorded and is told to check
  whether it took effect before running it again, unless CLAUDE_CODE_RESUME_INTERRUPTED_TURN is set."
  (https://code.claude.com/docs/en/sessions)
- Docs (env-vars): "`CLAUDE_CODE_RESUME_INTERRUPTED_TURN` | Set to `1` to automatically resume if
  the previous session ended mid-turn." ... "`CLAUDE_CODE_RESUME_INTERRUPTED_TURN_MAX_AGE_MS` ...
  Claude Code sets a one-hour bound itself when it restarts a crashed agent view session".
- Changelog (embedded, 2.1.286): "Fixed `claude --resume` and `--continue` sometimes losing every
  turn after a batch of parallel tool calls when the earlier session crashed or was killed."

**Loss summary for (1):** Esc-then-/exit loses the in-flight tool's result (recorded as
user-rejected), loses the rest of the turn (the model is told the user stopped it), and the
resumed process will NOT continue the turn on its own (Esc marker → kind none). A hard process
death mid-tool instead leaves a dangling tool_use; resume marks it "outcome unknown" (pL) and, with
`CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1` in the relaunch env, auto-continues the turn with "Continue
from where you left off.". Side effects of the cut tool (a half-run Bash) are not undone either way.

---

## (2) What survives a process exit / is restored on --resume

Restore dispatcher `Ict` @26049xxx (calls `ms`, `ps`, `us`, `cs`, `fs` @26049792):

| Thing | On interactive /exit | On --resume | Evidence |
|---|---|---|---|
| Background Bash (run_in_background) | Stopped. /exit with bg work shows "Background work is running / The following will stop when you exit:" with options "Exit and stop tasks", "Move to background and exit" (only when the bg handoff is available), "Stay" | Not restored. If no completion record: stopped + task-notification "No completion record was found ... may have been running when the previous Claude Code process exited. Check the output file for partial results" | @33564794, @33565567; `cs` @26064311; docs interactive-mode: "Background tasks are automatically cleaned up when Claude Code exits"; sessions: "Background Bash and monitor tasks aren't [restored]" |
| Monitor tasks | Stopped | Not restored | sessions doc (same line); agent-view: "running monitors ... stop with the process" |
| Background Agent subagents | In-process state lost | Orphan scan `us` @26055731: launched-by-Agent-tool with transcript mtime < 48 h (`rs=172800000` @26050111) handed to the "bg auto-resume path" (`eAo` @26059505: "automatically restarted from its saved transcript"); others marked stopped/failed with a note telling Claude to SendMessage-resume them (transcript saved) | @26056460–26061100 |
| Foreground Agent subagent mid-call | Its tool_use dangles | pL synthetic result; subagent transcript remains resumable by message | tLt/HDt above; changelog 2.1.288 "resumed subagents and teammates losing their earlier thinking and prompt cache" (fixed) |
| Workflow runs | Lost in-process | Marked stopped with "relaunch with Workflow({scriptPath, resumeFromRunId}) ... completed agent() calls return cached" | `fs` @26065485 |
| Session-only cron (/loop, CronCreate) | In-memory | "resurrected" from transcript (`ms` @26067689, recurring ones subject to `recurringMaxAgeMs`, one-shots only if next fire > now) | @26067689; docs sessions: "Session-scoped scheduled tasks: tasks that haven't expired are restored" |
| Durable cron | `.claude/scheduled_tasks.json` | survives | @9448384 "true = persist to .claude/scheduled_tasks.json and survive restarts" |
| ScheduleWakeup | pending wakeup record | restored by `ps` only if the persisted wakeup matches the transcript's last wakeup call and `scheduledFor > now` | @26068600 region |
| /goal | n/a | restored from the last `goal_status` attachment (`S5t` @5540803) with `iterations:0, setAt:now, origin:"restored", tokensAtStart:xm()`; event `tengu_goal_restored_on_resume` @36257174 | docs sessions: "Active goal ... carries over; its turn count, timer, and token-spend baseline reset" |
| Agent-team teammates (in-process) | die with the lead process; "teammates do not persist across sessions" @35771618 | lazily resumed by SendMessage: "Teammate X was not running; resumed it as an in-process teammate with N prior messages" @35483700 | |
| Remote (CCR) worker | — | orphaned bg tasks marked stopped `reason:"worker_restart"` with a "<system-reminder>The container was restarted…" note @26761519, @9631628 | |
| Usage-limit auto-continue wait | ends | "the wait doesn't restart when you resume the session"; also ended when "you switch accounts with /login" | interactive-mode doc |
| Permission "allow for this session" grants | lost across processes | — | sessions doc /branch table ("If you fork into a separate process ... re-approve there") |

Background (agent-view) sessions differ: their supervisor hands bg shells, dynamic workflows and
bg subagents to the next process (`HLr()` @19529451 = `!CLAUDE_DISABLE_ADOPT && !CLAUDE_CODE_DISABLE_BG_EXIT_HANDOFF`);
docs agent-view: "When a session's process stops or restarts, the background shell commands,
dynamic workflows, and background subagents Claude started in it carry over to its next process;
running monitors and shell commands a subagent started stop with the process."

---

## (3) Two live processes on one session jsonl

- Live-session registry: per-pid records listed by `listAllLiveSessions` (`qX` @9026467, chunk
  232z2cg3), each `{sessionId, kind: interactive|bg|daemon-worker, pid, procStart, ...}`.
- `e1e(sessionId)` @16275927 lists other live holders; `y8()` @16275308 returns a holder ONLY if
  `kind!=="interactive"`. CLI `--resume <id>` without `--fork-session` refuses only when a
  background holder exists (@19750306: `sue(...)` "is running in the background ... Add
  --fork-session to branch off a copy instead.").
- **Interactive vs interactive is NOT blocked.** Docs (sessions): "If you resume the same session in
  two terminals without forking, messages from both interleave into one transcript."
  (https://code.claude.com/docs/en/sessions). Agent view refuses only from its side:
  "Can't open — this session is running in another terminal" (`vHt` @16274705; respawn path
  @16312705 errorCode `resume_session_live_elsewhere`); `--bg --resume` of a live session starts a
  COPY: "note: session X is open in another Claude Code process, so this started a copy as Y" @16346110.
- **How a fork manifests:** each process appends rows whose `parentUuid` chains into its own
  in-memory history, so the jsonl becomes a tree with two leaves. The loader picks ONE leaf: `A$`
  @14257356 returns the leaf with the max `timestamp`; `MSt` walks parentUuid from it (@14293594).
  The other process's branch is invisible on the next resume. Listing with `keepAllLeaves:true`
  (`w6t` @14348718) yields one log entry per leaf (the picker groups them: "When the picker finds
  more than one entry for the same session, it groups them under a single row").
  `readEveryBranch` @26584589 is a fallback that re-reads keeping every branch to find a tool_use.
- **Per-config-dir scope (measured, `ls -ld`):** `~/.claude-next/{projects,sessions}` are symlinks
  to `~/.claude/...`, but `~/.claude-secondary`, `~/.claude-tertiary`, `~/.claude-quaternary` each
  have their own real `projects/` and `sessions/` directories. So the live-holder check of a process
  in one config dir cannot see a holder registered in another, and transcripts are per store (the
  incumbent transplants `<sid>.jsonl` and retires the source as `.jsonl.handed-off`, per
  lr-handoff.sh:1083-1087, 1307). A late append by the old process after a transplant lands in the
  old store's file: a silent fork with no CC-side detection.

---

## (4) Built-in account switch / process handoff

### /login in a live session
- Command def @10870894: `{type:"local-jsx", name:"login", description: logged-in ? "Switch Anthropic accounts" : "Sign in..."}` — no `immediate:!0`, so typed mid-turn it is QUEUED until the turn ends (docs interactive-mode: commands are held "until the turn ends", apart from immediate ones like /status).
- Post-login `NSe` @37348800: `o.onChangeAPIKey()`; computes `accountSwitched` (accountUuid
  changed); on switch disconnects Remote Control ("Account changed via /login — disconnecting
  Remote Control session"), clears bridge grouping, re-enrolls trusted device, refreshes policy
  limits; conversation messages are kept; `relaunching:false` for first-party.
- Token install `h1e` @26290830 → `Hxr` calls `Zoe(...preserveInProcessTokens:true, artifactAccount:"account_switch")`
  which deletes the stored credential entry and writes the new one — in THIS config dir's store
  (so every other session on that config dir sees the new account via its change check).
  `vun` @23523xxx clears provider/model caches, and when not same-account cancels quota auto-resume
  (`QL("account_switch")`, `_D("account_switch")`).
- Docs (authentication): "If you run `/login` while the variable is set, Claude Code switches the
  current session to the new login". Docs (interactive-mode, usage-limit wait): the wait ends when
  "you switch accounts with `/login`".
- Requires an interactive browser OAuth flow; not scriptable mid-turn.

### /logout
- Interactive `/logout` @42861379: `Zoe({clearOnboarding:true})` then `setTimeout(()=>Ts(0,"logout"),200)`
  — the PROCESS EXITS (in-flight turn dies). `Zoe` @23520140, first-party, without
  `preserveInProcessTokens`, REVOKES the refresh token server-side (`dA(refreshToken, clientId)`)
  and deletes the store entry. In a background session it refuses: "This background session shares
  credentials with other sessions; /logout here has no effect."
- So /logout+/login is strictly worse than /login: it kills the turn and revokes a token that
  sibling sessions sharing the keychain item may still be using.

### Process handoffs
- `/bg` / `←` (agent view): docs: "Backgrounding starts a fresh process that resumes from the saved
  conversation, and in-flight background work moves to it." "If Claude is responding when you run
  `/bg`, the response continues in the background session." Monitors stop. A foreground shell
  command still running is stopped after ~10 s. The supervisor "authenticate[s] with the same stored
  credentials as your interactive sessions" and with `CLAUDE_CONFIG_DIR` set "runs as a separate
  instance with its own sessions" — i.e. it does not change accounts.
- Built-in self-relaunch `z8` @16271153: flushes, then `spawnSync(claude, ["--resume", <sessionId>, ...extraArgs], {stdio:"inherit", env:{...process.env, ...e.env}})` and exits with the child's status. Used by gateway login and /tui. Same pane, same session id, env-overridable — but not user-invocable for an account change.
- `--fork-session`, `/branch`, `/fork`: always a copy under a new id (sessions doc).
- Teleport / Remote Control: same local process and account; RC is disconnected on account switch.

---

## (5) Prompt-cache implications of resuming on another account

- Docs (prompt-caching, "Cache scope"): "Caches are isolated between organizations" — each Max
  account is its own org, so the first request after a move reads NOTHING from cache: the whole
  context is re-processed and written (1-hour TTL write rate for the main conversation within plan
  usage). (https://code.claude.com/docs/en/prompt-caching)
- Resume itself keeps the transcript's original system prompt ("the resumed conversation keeps the
  system prompt it started with"), so a same-account resume within TTL hits cache; cross-account
  does not.
- Cold-resume quota dialog `pIe` @32345823: shown when the last message is older than the cache TTL
  OR the model changed, and the estimated share of the 5-hour limit ≥ `minPercent` (default 5,
  flag `tengu_amber_tally`). It does NOT consider an account change, and it is suppressed by the
  per-config `resumeReturnDismissed` flag. Docs (sessions): "The "Resume this conversation?" dialog
  ... can appear when you resume a long conversation after a long break or on a different model."
  A relaunched pane can therefore sit on this dialog.

## Answer (short)

See the structured return; the table and sections above are the detail.

## Command log (key outputs)

All run as `timeout 60 python3 -I /tmp/mtam/S04-cc-interrupt-resume-semantics/<script>` from /tmp.
- `g.py 'Request interrupted by user'` → 10 hits; constants @2677211/2677246, Yye list @2678868.
- `at.py 2677246 300 2200` → the ow/Au/PT/pL/fL/uv/LAe/NAe/rit/oit constant block.
- `g.py 'ensureToolResultPairing|...'` → @14146140 (strict-mode throw), @14146365 (tengu_tool_result_pairing_repaired).
- `at.py 14146140 4500 600` → body of `Ron` (pairing repair).
- `g.py 'tengu_resume[a-z_]*'` → 34 hits incl. tengu_resume_interrupted_turn @10982661.
- `at.py 10982661 5000 2500`, `at.py 10985300 0 2150`, `at.py 10987400 0 2700`, `at.py 10990000 2500 5500` → deserializeMessages `tLt`, `HDt`, `cmo`, `jDt`.
- `g.py 'function Np\('` → @4126254 `tengu_foamy_spring` default true.
- `g.py 'toolDenialKind:"interrupted"'` → @10990952, @18063521, @36470097.
- `g.py 'interruptedByShutdown'` → 27 hits; `CR` @14010954.
- `at.py 18063521 1500 1800` → createSyntheticErrorMessage.
- `at.py 18200820 1500 400` → `aborted_tools` path.
- `g.py '"user-cancel"'` → REPL cancel @33413021.
- `g.py 'orphaned_on_resume|...'` → @26055731 (agents), @26064311 (shells), @26065485 (workflows).
- `at.py 26056460 3500 3500`, `at.py 26064311 500 2300`, `at.py 26067300 0 1400` → orphan handlers, `ms` cron resurrection.
- `g.py 'tengu_goal_[a-z_]*'` → `tengu_goal_restored_on_resume` @36257174; `S5t` @5540803.
- `g.py 'worker_restart'` → @26761519 (CCR orphan note `Leo` @9631628).
- `g.py 'open in (another|other)'` → @16312716, @16346110, @36504680.
- `at.py 16346000 2500 900`, `g.py '(async )?function e1e\('` → `e1e`, `y8`, `sue` @16275xxx.
- `at.py 19750306 700 1500` → CLI --resume live check (non-interactive holders only).
- `g.py 'keepAllLeaves'`, `g.py 'function A\$\('` → leaf pick by max timestamp @14257356.
- `g.py 'Login successful'`, `at.py 37356899 3500 4000`, `at.py 37348800 0 5200` → /login `rIs`, `NSe`.
- `g.py 'name:"(login|logout)"'` → @10870894 command defs (no immediate flag).
- `g.py '[^\w$.]Zoe\('` + `at.py 23520140 0 3000`, `at.py 42861379 400 900`, `at.py 26290830 2200 900` → performLogout (revoke), /logout exits, /login token install.
- `g.py 'CLAUDE_CODE_DISABLE_BG_EXIT_HANDOFF'` → @19529451 `HLr`.
- `g.py 'Move to background and exit|Background work is running'` → @33564794, @33565567.
- `at.py 16271153 0 2400` → `z8` self-relaunch.
- `g.py 'inactiveMinutes'`, `at.py 32345823 1500 900` → cold-resume dialog `pIe`.
- `cl.py` + `grep -n -i -E 'resum|/login|...' changelog.txt` → changelog lines quoted above.
- `ls -ld ~/.claude*/{sessions,projects}` → next: symlinks to ~/.claude; secondary/tertiary/quaternary: real dirs.
