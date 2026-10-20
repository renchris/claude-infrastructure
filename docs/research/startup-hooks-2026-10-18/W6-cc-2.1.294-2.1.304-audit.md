# Claude Code 2.1.294-2.1.304: read-only audit before the 6.7 upgrade (2026-10-20)

Decision packet `5a7554481183` (Wave 6 item 6.7) ruled **wait**: at 2026-10-22T14:34Z, run
`/cc-upgrade` in the harness lane on the newest gate-passing release ≥2.1.301, after this audit,
and justify the move by its silent-loss fixes, not by per-hook timing. This file answers the
judge's four questions. Method: the CHANGELOG plus byte and `strings` reads of the binaries.
Nothing was launched, resumed, installed or switched.

## Answers

| # | Question | Answer | Conviction |
|---|---|---|---|
| Q1 | Does the 2.1.304 "resuming an inactive conversation" warning stall unattended resumes (`cc-lr switch`, limit-recover)? | **Not today: it cannot fire for this fleet.** It is a blocking dialog, but 2.1.293 already ships it under the same server flag, and its 5% bar is out of reach on Max 20x (a 1M-token context costs at most 0.92% on Opus 5.5 and 4.17% on Fable 5.1). If Anthropic lowers the bar, `lr-fire-resume.sh` would park the session (no data loss). | 85% |
| Q2 | Does `autoCompactEnabled=false` already turn off 2.1.299's default-on idle compaction? | **Yes.** Every binary read checks auto-compact before it reads `idleCompaction`. The pre-staged `"idleCompaction": false` is not needed. | 95% |
| Q3 | Does 2.1.299 running UserPromptSubmit hooks before skill expansion break ours? | **No.** The hook's `.prompt` was, and still is, the typed line (`/handoff …`), never the expanded skill text. A blocking hook now also stops the skill's `!` lines, which is safer. | 90% |
| Q4 | Does 2.1.300 drop keys our PreToolUse hooks return in `updatedInput`? | **No.** Every registered emitter returns only keys the tool declares. One untested risk: once the enforcement flag turns on, Edit's own read check runs on backup-before-write's rewritten real path. | 85% |

## Sources

| Item | Path | Version check |
|---|---|---|
| CHANGELOG | cached copy `/tmp/s67/changelog.md` (1,057,524 B; section headers: 2.1.304 line 3, 303 at 82, 302 at 86, 301 at 152, 300 at 206, 299 at 297, 296 at 490, 295 at 572, 294 at 718) | — |
| B293 (fleet pin) | `~/.claude-293/node_modules/@anthropic-ai/claude-code-darwin-arm64/claude` | `VERSION:"2.1.293"` |
| B301, B302 | `~/.cursor/extensions/anthropic.claude-code-2.1.30{1,2}-darwin-arm64/resources/native-binary/claude` | `VERSION:"2.1.301"`, `"2.1.302"` |
| B304 | a c10-batch `--check` scratch tree under `$TMPDIR` (`.claude-versions/2.1.304/…/claude`); temporary, may be gone | `2.1.304` only |

No 2.1.294-2.1.300 binary was on disk, so the 2.1.299 and 2.1.300 answers rest on code read in
B293 (before) and B301/B302/B304 (after). Offsets below are byte offsets in the binary. Version
check: `python3 -I -c "import re,sys;d=open(sys.argv[1],'rb').read();print(set(re.findall(rb'VERSION:\"(2\.1\.\d+)\"',d)))" <bin>`.
One-pass reproduction of the key strings:
`strings -n 12 <bin> | LC_ALL=C grep -o -F -e 'Resume this conversation?' -e 'tengu_amber_tally' -e 'initialMessage===null)this.maybePromptStaleResume' -e 'return"compaction_off";if(!' -e 'key(s) that the tool' -e 'tengu_glimmering_newt' | sort | uniq -c`.
B293 has the first four and lacks the last two; B304 has all six.

## Q1. The resume warning

CHANGELOG 2.1.304 (line 11): "Added a warning on Pro and Max plans when resuming an inactive
conversation would use a noticeable share of your 5-hour usage limit…".

- **It is a modal Select.** B304 `function mrt({inactiveSince,contextTokens,percentOfFiveHourLimit,…})`
  (offset 247418427) renders `title:"Resume this conversation?"` with options Resume / Start a new
  conversation; Esc means resume (`onCancel:()=>Ee("dismiss")`). Default focus is **Resume** (the
  `tengu_stateful_mitten` flag that would move it is absent from all four account caches).
- **Where it runs.** The startup path calls it only when `initialMessage===null`, so an interactive
  `claude --resume <id>` launched **without** a positional prompt; also in-app `/resume`. 2.1.304
  adds an idle trigger, suppressed while a dialog is on screen or the account is past its limit.
  `-p` always carries a prompt, so the startup gate is unreachable there (inferred, 80%).
  `bin/reso-resume-one` passes the prompt positionally and never meets the dialog.
- **The gate** (`voe`, offset 246319337) skips the dialog when the `tengu_amber_tally` config fails
  to parse, `resumeReturnDismissed` is set, prompt caching is off, the account is past a usage
  limit (new in 304), or the cache is warm and the model unchanged. Otherwise it shows when
  `contextTokens/1e6 × creditsPerMillionTokens[model] × 100 / fiveHourCredits[tier] ≥ minPercent` (5).
- **2.1.293 already has it** (function `pIe`, offset 214764270), same flag and gates minus the
  304-only additions. Moving the pin does not create the exposure.
- **Live payload** (all four accounts' `cachedGrowthBookFeatures`): `minPercent 5`,
  `fiveHourCredits.default_claude_max_20x 200000`, `creditsPerMillionTokens` Opus 5.5 1833,
  Fable 5.1 8333; every account is `default_claude_max_20x`; `resumeReturnDismissed` is unset.
  Opus 5.5 would need ~5.46M tokens and Fable 5.1 ~1.2M to reach 5%.
- **If the payload changes**, `scripts/limit-recover/lr-fire-resume.sh` would stall:
  `CLAUDE_CODE_RESUME_THRESHOLD_MINUTES` (lines 1077-1078) silences only the older "This session is
  X old" dialog; `LR_RE_MENU='❯1. Resume'` (line 1088) matches the new one, but `answer_menu 1` sends
  Down to option 2, fails its readback, and parks with the selector on "Start a new conversation".
  `handoff-fire` relaunches without a prompt too, so it is equally exposed. Closures, any one:
  `resumeReturnDismissed: true` in each `.claude.json` (a config change, the operator's); pass the
  resume prompt positionally as `reso-resume-one` does; or an expect arm on `Resume this
  conversation?` that answers Resume after a readback. **Add a check for this to the
  `/cc-upgrade` gate**, since its trigger is a server-side change, not the pin.

## Q2. Idle compaction

CHANGELOG 2.1.299 (lines 300-301): idle compaction of a 200K+ conversation left idle ~54 minutes;
`"idleCompaction": false` turns it off. Code, the same order in every binary read:

- B304 terminal path (offset 225323423): `function x6o(…){if(e.mode==="off")return"disabled";if(!of())return"compaction_off";if(!Xct())return"idle_compaction_off";…`,
  with `of()` = `ks("autoCompactEnabled",!0).value` (unless `DISABLE_COMPACT`) and `Xct()` = `ks("idleCompaction",!0).value`.
- B304 SleepCompactor (offset 260723772): the same order.
- B293 `aio` (offset 193075377), B301 `Ajo` (205289677), B302 `k1o` (222356721): the same order.

`~/.claude/settings.json` has `autoCompactEnabled: false` (every account links to it), so idle
compaction returns `compaction_off` before `idleCompaction` is read. Note: the rollout flag
`tengu_sunny_locket` is already served as `{"mode":"compact"}` to one account on 2.1.293; this gate
is what keeps it off.

## Q3. UserPromptSubmit before skill expansion

CHANGELOG 2.1.299 (line 465): hooks now run before a skill or custom slash command expands, so a
blocking hook also stops its embedded shell lines. (Line 466 concerns skill front-matter hooks; we
have none: `grep -l '^hooks:' ~/.claude/skills/*/SKILL.md` is empty.)

- The hook input is `{…,hook_event_name:"UserPromptSubmit",prompt:e,session_title}` in both B293
  (offset 195028665) and B304 (offset 227232846). In B304 a command's `submission.text` is the typed
  line unless a mod rewrote its arguments (`vs()`, offset 232926826).
- Our 7 UserPromptSubmit hooks (live and template agree): handed-off-session-guard (reads no
  prompt; a block now also stops `!` lines), cache-expiry-warning (leading `<task-notification>`
  only), memory-nudge (typed text, skips `<…` and >4000 chars), handoff-intent-nudge
  (`"/handoff"*` still matches), research-precognition-nudge (`/research` regex), session-beat
  (operator presence; slash commands count), mailbox-drain prompt (reads no prompt). None depends on
  expanded text. Every `/ship` matcher is on Stop, PreToolUse, TaskCompleted or SessionEnd.
- Residual (inferred): hooks may now also fire for a forked (`context: fork`) skill, which B293
  skipped. A hook pass, not a correctness change.

## Q4. `updatedInput` validation

CHANGELOG 2.1.300 (line 272): `updatedInput` from PreToolUse and PermissionRequest hooks is now
validated like Claude's own input; unknown keys are dropped and input the tool rejects denies the call.

B304 `IGe` (offset 224684071): (1) `inputSchema.safeParse` — any issue other than an unknown key
denies (B293 already did this); (2) enforcement switch `Z() || ui("tengu_glimmering_newt")`, a flag
absent from all four account caches; (3) `__artifact*` keys denied; (4) unknown keys stripped;
(5) under enforcement, the tool's own `validate` runs on the rewrite; (6) a warn line
"dropped/kept N key(s) that the tool's schema does not know"; (7) PreToolUse does not restore
echoed-back keys.

| Emitter (registered?) | Tool | Keys | Unknown keys? |
|---|---|---|---|
| qos-rewrite.sh (live, PreToolUse Bash) | Bash | `{command}` (line 122) | none |
| coldcompile-admit.sh (live, PreToolUse Bash) | Bash | `{command}` (line 212) | none |
| curl-gate.py via curl-gate-scope.sh (live, project-scoped) | Bash | `{command}` (line 201) | none |
| backup-before-write.sh (live, Write/Edit/MultiEdit) | Write/Edit/MultiEdit | the tool input with `file_path` set to the real path, auto-memory paths only (lines 50-77) | none |
| ms365-shared-guard.sh (not registered anywhere) | mcp__ms365__* | tool input + `account` | only matters if registered |

PermissionRequest hooks emit no `updatedInput`. Residual risks, both unverified:
1. **backup-before-write vs Edit's read check.** Under enforcement, Edit's `validateInput` ("File has
   not been read yet…", offset 216885885) runs on the rewritten real path. If read-state is keyed by
   the spelled path, a Read-then-Edit of a memory file through `~/.claude-next/…` would be denied.
   **One headless gate test on the candidate binary should cover it in `/cc-upgrade`.**
2. Whether `{command}`-only rewrites keep Bash's `run_in_background`/`timeout`/`description` is
   pre-existing B293 behavior, not a 2.1.300 change.

## Silent-loss fixes in 2.1.294-2.1.304 (the upgrade's justification)

CHANGELOG line numbers in brackets; [n/a] does not reach this fleet.

- **2.1.300:** [229] the first transcript entry after a resume was lost when a crash had cut the last
  line (limit-recover and resume paths); [218] SessionEnd hooks skipped on exit while a background
  command ran; [244], [247] headless/SDK resumes lost compaction-kept messages or the summary.
- **2.1.299:** [423] turns ended silently after a non-streaming fallback at the output limit;
  [345] document blocks dropped from a message sent mid-work; [424] Write silently re-encoded
  non-UTF-8 files (now refused); [410] a custom command's shell line ran twice; [421] background
  subagents reported twice; [422] SendMessage lost a subagent by name after resume; [371] the
  2.1.296 double tool-call regression (why 2.1.296-2.1.298 are excluded).
- **2.1.301:** [160] quitting removed a WorktreeCreate-hook worktree without asking (untracked and
  ignored files, not commits); [164] workflow agents skipped their step while the run reported
  success; [163] Grep/Glob reported no matches when the search program failed; [171] sign-outs
  after a short `claude auth status` or `claude plugin list`.
- **2.1.302:** [96] subcommands exited before a queued settings/config write finished.
- **2.1.304:** [32] subagents forgot their latest work when messaged or resumed right after
  finishing; [42] approving an agent-team shutdown exited the whole CLI; [39] Bash deleted a large
  output file it could not copy; [15] LOCAL_GC drop [n/a]; [34] `claude --worktree` branch deletion
  [n/a] (every fleet worktree is hook-made).
- **2.1.296:** [505] resumed subagents told a shutdown-interrupted call was rejected; [523] Edit
  replaced non-ASCII in non-UTF-8 files; [525] a prompt sent during SessionStart hooks vanished on
  `←`; [510] Esc during a UserPromptSubmit hook let an unchecked prompt through headless.
- **2.1.295:** [651] an async hook's multi-line JSON output was ignored (**we run 5 async
  SessionStart hooks**); [643] an async SessionStart hook's context re-added on every resume;
  [590] `-p` text output dropped earlier responses; [661] Edit treated a file as fully read when it
  changed without an mtime advance.
- **2.1.294:** prompt and agent hooks written as instructions allowed what they should block.

Behavior shifts for the gate (not losses): [269] 2.1.300 transcripts also record each request's
system prompt, tools and parameters, so they grow (our transcript scanners and disk); [263] 2.1.300
force-kills background commands 1.5 s after exit asks them to stop; 2.1.302 turns fork subagents
on by default in `-p`.

## Not checked

The Fable 5.1 context window (above ~1.2M tokens a Fable session could cross 5%); how `Z()`
resolves; Edit read-state key normalization; whether the resume driver's READY match could fire
before the dialog mounts.
