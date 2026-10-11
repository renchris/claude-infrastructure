# Adversarial verification of the candidate fixes (2026-10-11)

Two independent reviewers (safety lens, efficacy lens) judged each candidate in design.md.

## safety lens

### C1-rm-prompt-preempt: revise

The hook only ever denies, so it cannot let a removal through. In 2.1.293's runHooks, a PermissionRequest `deny` goes straight to buildDeny(message). Only `allow` reaches handleHookAllow. The proposal does not set `interrupt`, so the session is not aborted.

The problem is the recipe text. When the hook denies, its message replaces Claude Code's own deny text (/tmp/cc293-strings.txt offset 7481120). That text says: "Only a person may approve such a removal ... Do not work around the check by splitting, scripting, or re-issuing the removal through another tool or shell." The proposed inline_shell recipe says the opposite: it tells the model to "Write the script to a file and run `bash /tmp/<name>.sh`". This goes to every inline-shell match, including the 3 G4 scripts that really contain `rm -rf $T`.

A script file hides the removal from both of our checks. The dangerous-rm check flagged 0 of 430 `bash /tmp/x.sh` calls, and validate-bash.sh scans only the command string. The only guard left would be a line of prose inside the file. validate-bash.sh:2251 already tells subagents the opposite ("no find -delete, python, rsync or a script file"), and subagents are the population this hook mostly hits.

A smaller issue: the companion change that stops paging is gated on the hook being registered. If the hook crashes or times out, nobody is paged.

**Revised change:**

Same three files, migration, kill switches and acceptance probe as proposed. Changes:

(1) Every recipe includes Claude Code's own sentence: "Only a person may approve a removal this check stops; do not work around it by splitting, scripting, or re-issuing the removal through another tool or shell."

(2) The inline_shell recipe branches on whether the -c script contains a removal word (rm, rmdir, unlink, shred, `find … -delete`, `-exec rm`):
- No removal (G1): keep the current text, "run the statements directly, or Write the script to a file and run `bash /tmp/<name>.sh`".
- Removal present (G4): "Re-issue it without the -c wrapper and run the statements directly in this Bash call, so the check can read the removal. Each rm target must be a literal absolute path or \"${VAR:?}\"-guarded. Do not move the removal into a script file, python, find -delete or another shell."

(3) Additions to tests/rm-prompt-preempt.bats:
- across every positive, the output never contains "behavior":"allow" or updatedInput, and the script source has no allow branch;
- the 3 G4 positives get the no-script-file recipe.

(4) In lead-supervisor.sh and notify.sh, suppress a page only when rm-prompt-preempt.jsonl has a row for this session and command from the last 30 s, rather than whenever the hook is registered. A hook that fails then still pages.

### C2-workflow-lean-shell-rule: revise

This is guidance only and grants nothing. Rule (1), though, offers "Write the script to a file and run `bash /tmp/<name>.sh`" with no condition, so an agent can read it as covering scripts that remove files. The closing line "A script file is not a way around (2) or (3)" is a self-policed constraint and nothing enforces it. Neither the dangerous-rm check nor validate-bash.sh looks inside `bash file.sh`.

Both Claude Code's deny text ("Do not work around the check by splitting, scripting, or re-issuing") and validate-bash.sh:2251 ("no ... script file") forbid moving a removal into a script. The same guidance should not offer that path to workflow-lean agents, which caused 42 of the 64 hits.

One factual error: "no allow rule or hook can approve it". mechanics.md §c shows that a PermissionRequest hook `allow` does resolve the dialog.

**Revised change:**

Append under 'Tool behaviour' in agents/workflow-lean.md, and the same bullet to agents/deep-research.md:
"- Claude Code's built-in removal check holds a 2-minute prompt and then **denies** the call when nobody answers; no allow rule can approve it. Keep commands readable to it.
  (1) No `bash -c '…'`/`sh -c '…'` around a function, a `\"$@\"` runner, a `$VAR` used as a command, `source`/`eval`, `set --` or `{a,b}`, even with no rm in it. Run the statements directly in the Bash call. Only a script that removes nothing may instead be written to a file and run as `bash /tmp/<name>.sh`.
  (2) Every rm/rmdir target is a literal absolute path or `\"${VAR:?}\"`-guarded, never `$D/*` or `\"$D\"/*`.
  (3) Never `cd X; rm rel/*`; write `rm -f /abs/X/rel/*`.
  (4) Never move a removal into a script file, python, `find -delete` or another shell to get past the check. If a removal is still refused, report the exact command to your caller."

### C3-global-and-agent-browser-guidance: revise

Two problems.

(a) The global bullet has the same flaw as C2. Its "(run the statements directly, or write a script file and run `bash <file>`)" has no condition, so it reads as permission to move a removal into a file. That is the workaround both Claude Code's deny text and validate-bash.sh:2251 forbid.

(b) The agent-browser advice would move browser calls off the deterministic allow rule and onto the classifier. On 2.1.293 in final/corpus.json:
- function-alias calls (`ab(){ agent-browser --session x "$@"; }; ab …`): 1,066 of 1,067 were decided by the auto-mode classifier (pdreason=classifier);
- literal `agent-browser --session x <verb>` calls: 296 of 354 were allowed by rules through the existing `Bash(agent-browser:*)`.

Every call routed through the classifier can be denied, counts toward the 3-consecutive-denial limit that produces the F1 timed fallback, and is exposed to the 120–240 s stage-2 stalls. The alias also contradicts skills/agent-browser/SKILL.md:94-96, which already shows the literal form.

**Revised change:**

CLAUDE.global.slim.md, § Working rules, one bullet:
"- Claude Code's built-in removal check prompts for 2 minutes and then denies when nobody answers; no allow rule clears it. Keep commands readable to it:
  - no `bash -c '…'` wrapper around functions, `\"$@\"` runners, `$VAR` commands, `source`/`eval` or `set --`; run the statements directly, or, only for a script that removes nothing, write it to a file and run `bash <file>`;
  - give rm a literal absolute path or `\"${VAR:?}\"`, and never `cd X; rm rel/*`;
  - never move a removal into a script file, python, `find -delete` or another shell to get past the check."

skills/agent-browser/SKILL.md:
"Pass the session on every call as literal text, `agent-browser --session <name> <verb> …`. That form matches the existing `Bash(agent-browser:*)` allow. Never use a function alias (`AB(){ …; }; AB …`) or `AB=\"agent-browser …\"; $AB …`: they match no allow rule, so every call goes to the auto-mode classifier. Clear a screenshot dir with `rm -f /abs/dir/*.jpg` or `rm -f \"${D:?}\"/*.jpg`."

Rerun the instruction-budget gate after the edit.

### C4-autodeny-census-telemetry: revise

The census itself is read-only apart from its own append-only log, so it is safe.

The optional beacon re-key is not. It would change hooks/cc-permission-beacon.sh to write `$SID.$AGENT_ID.json`, but consumers look the beacon up by exact `<sid>.json`. For example, bin/cc-classify:785 reads `bf="$PERMPEND_DIR/$sid.json"`. The beacon's documented all-clear contract (cc-permission-beacon.sh:87, "dir present, no <sid>.json ⇒ genuinely nothing pending") would then report a subagent's pending prompt as nothing pending. lead-supervisor, cc-blockers, cc-queue, cc-pane-headless and permission-denied.sh also read this store. The re-key would reduce oversight of exactly the unattended prompts this work targets, so it should come out of this change.

A smaller issue: copying whole commands into a new long-lived log adds another copy of any inline secrets.

**Revised change:**

Add bin/cc-autodeny-census as proposed: read-only, rg -l prefilter, dedup by tool_use_id, the outcome, cause, context, agent-type and version fields, and the weekly `cc-autodeny-census --since 7d` step in skills/permission-harvest/SKILL.md. Changes:

(a) Each row in ~/.claude/logs/autodeny.jsonl stores cmd_head, at most 200 characters, plus sha256 of the full command, never the full text.

(b) The two inferred row kinds carry `inferred:true` and their method name.

(c) Drop the optional per-agent beacon re-key from this change. If it is pursued later, it needs every `<sid>.json` consumer migrated in the same diff (cc-classify:785 and the others above) and bats coverage of the all-clear contract.

### C5-fallback-narrow-allow-rules: keep

I tried to make these rules let a destructive or exfiltrating action through and could not.

- **Matching.** Bash prefix rules in 2.1.293 match `Ce===Te || Ce.startsWith(Te+" ")`, so they need a word boundary. They are checked per subcommand, and a subcommand that still splits is refused (`if(he.get(Se))return!1`). `~/.claude/bin/cc-notify x && rm -rf ~` therefore still needs its own approval for the rm, and `cc-notify-evil` does not match.
- **cc-notify.** All three spellings resolve to one file: ~/.claude/bin/cc-notify is a symlink to ~/Development/claude-infrastructure/bin/cc-notify. That same binary is already granted as `Bash(cc-notify:*)`. The classifier's [Auto-Mode Bypass] catch on the absolute spelling was never a real control, because the bare name already bypasses it.
- **wrap-ledger.sh.** Its only flags are --machine, --busy, --full, --goal, --session and --transcript. It writes only its memo cache and lock directories, and it starts detached `cc-backlog list` cache fills. Stop hooks already run it unattended.
- **Auto mode.** None of the five rules matches the interpreter-wildcard shapes that auto mode strips (Ydr/tIn).

The benefit is small, about 1–3 prompts in 6 weeks, but it costs no safety.

### C6-disable-inline-shell-rm-prompt: reject

This removes a safety rail and gains nothing over the revised C1–C3.

With it set, Claude Code no longer inspects `-c` scripts it cannot read, including the 3 G4 scripts that really run `rm -rf $T` on a variable target. validate-bash.sh scans `-c` strings with regexes only. Claude Code's own deny text says only a person may approve such a removal.

lead-notes.md also lists this env var among the operator-only switches that are "NOT ours to flip". The false positives it would remove (G1) are handled by the C1 deny recipe and by C2/C3 guidance without turning the check off.

## efficacy lens

### C1-rm-prompt-preempt: revise

Effective, with two gaps.

The claimed coverage holds up:
- I re-ran prfinal.shape over all 64 rows in final/rows.json. It matched 41 of the 50 timed rows: 6 main sessions and 35 workflow agents (29 workflow-lean, 6 workflow-subagent).
- It also matched 10 of the 11 capped rows and 3 of the 3 immediate rows. Those are unreachable, because wln() denies them before any hook runs.

The mechanism checks out in the 2.1.293 binary:
- The interactive ask handler runs PermissionRequest hooks in parallel with the dialog (`if(!_&&r.personOnly!==!0)(async()=>{…s.runHooks…; k(q)})`).
- The runHooks deny branch returns buildDeny(message), and its output format is the expected `{behavior:"deny",message}`.
- Once the dialog is claimed, the timer callback does nothing (`if(!k())return`). So an expired timer never fires, and the 3-per-session counter that leads to the cap does not grow.
- The beacon is a matcher-"" PermissionRequest hook. Its archive rows matched 4 main and 21 workflow timed dialogs, which proves these hooks run for workflow-agent dialogs.

Gap 1, permission mode. wln() is called only when LLe(mode) is true (auto, or plan with auto active) or the mode is bypassPermissions. In default and acceptEdits modes the same safety ask is an ordinary dialog with no timer. As written, the hook would deny those too: the person loses the choice and nothing is gained. Gating on permission_mode, which is in the hook input via xd(), costs 0 of the 41 rows.

Gap 2, the probe. The only workflow evidence so far is that the hook RUNS. Nothing shows that a hook deny resolves a workflow dialog, and 35 of the 41 rows depend on it. The proposed probe tests only a main-thread call and does not set auto mode.

**Revised change:**

Same files, registration and companion changes as proposed, plus:

(1) In hooks/rm-prompt-preempt.sh, directly after the tool_name check:
`mode="$(jq -r '.permission_mode // empty' <<<"$in")"; case "$mode" in auto|bypassPermissions|plan) ;; *) exit 0 ;; esac`
Comment: in 2.1.293 the 120 s timer exists only in these modes (wln is gated on LLe(mode) or bypassPermissions). In default and acceptEdits the safety dialog waits for the person and must pass through.

(2) Add a bats negative: an inline_shell positive with permission_mode=default passes through silently.

(3) Run the acceptance probe with `--permission-mode auto` and the --settings overlay. Fire `bash -c 'f(){ "$@"; }; f true'` twice:
- (a) from the main thread;
- (b) from a Workflow slot with agentType workflow-lean.
Pass only if both return the hook's deny text in under 5 s.

(4) State expected coverage as: 41 of 50 timed rows (6 main, 35 workflow). Capped and immediate rows are not reachable directly, but cap accrual stops for the matched shapes.

### C2-workflow-lean-shell-rule: revise

Right place, but the recipe is wrong in this environment.

Why the place is right:
- I joined each row to its subagent .meta.json. Of the timed rows, 31 come from workflow-lean and 1 from deep-research. The same types account for 11 capped and 3 immediate rows: 46 rows in all, 32 of them timed. C1 cannot reach the 14 capped and immediate rows, and C2 also reaches 3 timed rows C1 misses.
- So the claimed 45 mixes outcomes. The timed figure is 32.

Why the recipe fails:
- The Bash tool runs zsh (measured: ZSH_VERSION=5.9).
- zsh does not word-split an unquoted `$VAR`. Measured: `AB="echo hello world"; $AB` gives `command not found: echo hello world`.
- So "run the statements directly in the Bash call" breaks the `$AB` agent-browser rows (5 timed). It also breaks the sourced bash-library rows (`. lib.sh`, `source <(sed …)`), which is likely why agents wrapped them in bash -c in the first place.
- A top-level function works in zsh (measured: `f(){…"$@";}; f a b`). So does a script file run with `bash /tmp/x.sh` (430 uses, 0 flagged).

Two smaller problems:
- "no allow rule or hook can approve it" is false: a PermissionRequest hook can, and C1 is one.
- workflow-lean.md already teaches `timeout 270 bash -c '…'`. That form is unflagged only while the body has none of the listed constructs, so the rule should say so.

**Revised change:**

Append under 'Tool behaviour' in agents/workflow-lean.md, and the same bullet in agents/deep-research.md:
"- Claude Code's built-in removal check holds a 2-minute prompt and then **denies** the call when nobody answers; no allow rule can approve it. Keep commands readable to it. (1) No `bash -c '…'`/`sh -c '…'` around a function, a `"$@"` runner, a `$VAR` used as a command, `source`/`.`/`eval`, `set --` or `{a,b}`, even with no rm in it: Write the script to a file and run `bash /tmp/<name>.sh` (`timeout N bash /tmp/<name>.sh` for a bound). A plain `timeout N bash -c '<loop>'` with none of those is fine. Do not just unwrap bash code into the call: the Bash tool runs zsh, which does not word-split `$VAR`, so `AB="agent-browser --session x"; $AB open …` fails. Bind a multi-word command as a function instead: `AB(){ agent-browser --session x "$@"; }`. (2) Every rm/rmdir target is a literal absolute path or `"${VAR:?}"`-guarded, never `$D/*` or `"$D"/*`. (3) Never `cd X; rm rel/*`; write `rm -f /abs/X/rel/*`. A script file is not a way around (2) or (3)."

Expected: up to 32 timed rows (31 workflow-lean, 1 deep-research), plus 14 capped or immediate rows that C1 cannot reach. Compliance is unmeasured.

### C3-global-and-agent-browser-guidance: revise

Reach: 18 timed rows (10 main, 8 workflow-subagent).
- One main row is a deliberate `rm -f ""` probe, so at most 17 can be helped.
- C1 already covers 12 of the 18, and its deny text gives the same recipe at the moment it is needed. C3's unique reach is 5 rows: 3 main and 2 workflow-subagent.

Three problems:
- **Budget.** The global bullet cannot land as specified. `hooks/lib/instruction_budget.py assert --class user` reports BREACH: 60,954 > 60,000. config/instruction-budget.json has enforce=true, and the slim global is "one-in-one-out". A +350-char edit to CLAUDE.global.slim.md is a growth past budget, so the Write/Edit gate refuses it. "Rerun the budget gate" understates this.
- **The agent-browser edit misses its rows.** All 9 agent-browser rows are workflow-lean, and that agent type loads no skills, so the SKILL.md edit reaches none of them. Its value is indirect: SKILL.md line 15 says the examples "omit [--session] for brevity", which invites the `AB=…; $AB` binding in briefs that leads write.
- **Same zsh trap as C2.** "run the statements directly" fails for `$VAR` commands and bash-only code.

**Revised change:**

(1) Edit CLAUDE.global.slim.md only as a one-in-one-out trade: in the same edit, remove at least as many characters as are added. Use this wording:
"- Claude Code's built-in removal check prompts for 2 minutes, then denies; no allow rule clears it. No `bash -c '…'` around functions, `\"$@\"` runners, `$VAR` commands, `source`/`eval` or `set --`: write a script file and run `bash <file>` (the Bash tool is zsh, which does not word-split `$VAR`; bind multi-word commands as functions). Give rm a literal absolute path or `\"${VAR:?}\"`; never `cd X; rm rel/*`."
If no trade is acceptable, skip the global edit and rely on C1's deny text for main and workflow-subagent contexts.

(2) Keep the skills/agent-browser/SKILL.md change, placed next to line 15: "Carry --session with a top-level function, `AB(){ agent-browser --session <name> \"$@\"; }`, never `AB=\"agent-browser …\"; $AB …` (zsh will not split it, and inside `bash -c` it trips the removal check). Clear a screenshot dir with `rm -f /abs/dir/*.jpg` or `rm -f \"${D:?}\"/*.jpg`."

Expected: at most 17 timed rows reachable, 5 of them not covered by C1. The agent-browser edit reaches 0 census rows directly.

### C4-autodeny-census-telemetry: revise

This candidate prevents 0 prompts. It answers the operator's "do we have a record of all of them" question and gives C1 and C2 a before/after measure, so it stays, with three fixes to the fallback inference.

What I confirmed:
- **The "third denial" heuristic is right.** In iTr the call order is `Ri=CF(M,Eqe)` (increment) and then `iTr(Ri,…)` with `consecutiveDenials>=3`. So the timed fallback is the 3rd consecutive classifier block, and "preceded by at least 2" is correct. mechanics.md's "4th or later" marker is wrong.
- **Profiles.** tengu_ticklish_whisper is cached true in the -next, -secondary, -tertiary and -quaternary .claude.json files, and unset in ~/.claude.
- **Store layout.** ~/.claude-next/projects is a symlink to ~/.claude/projects, so a session's store does not tell you its account flag. ~/.claude-next4/projects is a separate store with 0 hits.

The three fixes:
- **Counter resets.** With the flag on, rule and fast-path allows do not reset the consecutive counter (`if(!f1(...))CF(M,$M)`); only classifier allows do. A transcript counter that resets on any successful call will undercount streaks.
- **Slow errors.** Stage-2 classifier errors also take 120–242 s; the per-store TSVs list at least 6. The deny must carry its reason and elapsed time so a slow error is not called a fallback.
- **Drop the beacon re-keying.** It touches mature Stop-clear logic, and C1's own log plus the transcript scan already give a complete safety-check record.

**Revised change:**

Add bin/cc-autodeny-census as proposed, with these changes:

(a) Discover stores by globbing `~/.claude*/projects` and deduplicating by realpath, rather than hard-coding 4.

(b) Fallback-timeout inference:
- count consecutive classifier denies, resetting only on a classifier-decided allow, never on a rule or fast-path allow;
- the 3rd deny qualifies when its elapsed time is at least 120 s;
- record the deny reason and elapsed time;
- label a row `inferred_fallback_or_slow_classifier` when the reason contains "Stage 2 classifier error" or "unavailable".
All inferred rows stay labelled inferred.

(c) Remove the optional cc-permission-beacon.sh re-keying.

Keep the weekly `cc-autodeny-census --since 7d` step in skills/permission-harvest/SKILL.md. Report C1's rm-prompt-preempt.jsonl count next to it, so a C1-resolved dialog can be told apart from an expired one.

Expected prompts eliminated: 0 (measurement only).

### C5-fallback-narrow-allow-rules: keep

Verified against the per-store TSVs.

The 3 inferred fallbacks:
- **2026-09-26, high confidence.** The streak was a heredoc brief [Security Weaken], then `~/Development/claude-infrastructure/bin/cc-notify …`, then cc-backlog --help as the timed 3rd. The new rule removes the cc-notify deny, so the streak stops at 2.
- **2026-09-24, probable.** The 2nd deny was the compound `git ls-remote …; ~/.claude/bin/cc-notify …`. `Bash(git ls-remote:*)` is already allowed, so with this rule every part of the compound is rule-allowed and it never reaches the classifier.
- **2026-09-21.** The kitty @ launch streak is not covered.

That is 2 of 3, matching the claim. Allowlist allows do not reset the counter when the flag is on; they only remove denies, which is enough here.

The rules are safe in auto mode:
- They are not stripped there. isDangerousBashPermission/tIn strips only `bash`, `bash:*`, `bash *`, `bash*` or `bash -…*`, and `bash ~/.claude/scripts/wrap-ledger.sh:*` hits none of those.
- `~`-prefixed Bash rules are already established (`Bash(~/.claude/scripts/handoff-fire.sh:*)`).
- All account settings.json files are symlinks to ~/.claude/settings.json, so one edit covers every account.

Impact is small: 0 inferred fallbacks since 2026-09-26. The rules also take wrap-ledger off the slow classifier path (one 242 s stage-2 stall). Operator-applied through permission-harvest, as stated.

### C6-disable-inline-shell-rm-prompt: reject

It would work, but C1 plus C2 do the same job without removing a safety rail.

What the flag does in 2.1.293: `async function k_e(…){if(a.CLAUDE_CODE_DISABLE_INLINE_SHELL_RM_PROMPT||!Y3())return null;…}`. That disables the whole inline-shell scan, not just its unreadable-script branch. As far as I can tell from the code layout, it also covers ASr, the variable-target rm check inside `-c` scripts that it can parse.

Its reach: the dialog never appears for 37 timed rows (34 in G1, 3 in G4), 5 capped and 1 immediate. Those commands then go to the classifier and would usually run. On this axis it beats C1, whose deny costs one rewrite turn.

Why it is still rejected:
- It applies to every session, account and mode.
- It drops Claude Code's only parsed check for an empty-variable `rm -rf` inside `-c`, which is what the 3 G4 rows really contained. The classifier and validate-bash's regexes are the only checks left.
- Lead notes class these env kill switches as operator-owned safety rails.

C1 (41 timed) and C2 (32 timed, plus 14 capped or immediate) cover the same rows without that loss. Reconsider only if C1's acceptance probe shows a hook deny does not resolve a workflow dialog.
