# Timed auto-deny prompts: census and allowlist/hook design (2026-10-11)

Read-only investigation. Everything here was measured against local transcripts and the CC 2.1.293
binary strings dump; files cited live under `/tmp/autodeny-census/`. Repo paths are relative to
`/Users/chrisren/Development/.worktrees/wt-cc-174746-13116`.

## 1. Headline counts

**Dangerous-rm safety check (`dangerousRemoval`, the "will automatically deny in M:SS" dialog):
64 auto-denies, 2026-09-29 00:28Z to 2026-10-11 23:04Z.**
Source: `final/hits.json`, `final/autodeny-64.tsv`, deduplicated by tool_use_id. The raw rows
total 82: `~/.claude-quaternary` 40, `~/.claude` 28, `~/.claude-tertiary` 8, `~/.claude-secondary` 6.
18 of those are the same tool call copied between account stores.

| outcome | n | meaning |
|---|---|---|
| timed out | 50 | Dialog shown, nobody answered, denied after 120.1–170.7 s |
| capped | 11 | Denied with no dialog because the session had already let 3 dialogs expire (all workflow agents; 6 in session 58d3640a) |
| immediate | 3 | Plain subagent that cannot prompt; denied in under 1 s |

- **Context:** 51 workflow agents (**42 of them `workflow-lean`**, which loads no CLAUDE.md), 10 main sessions, 3 subagents.
- **Version:** 57 on 2.1.293, 7 on 2.1.284. The safety timer first appears in 2.1.284.
- **Accelerating:** 48 of the 64 fell on 10-10 and 10-11. The inline-shell branch of the check first fired on 2026-10-08, one day after 2.1.293 appeared (2026-10-07 22:05Z).
- **Answered in time:** about 23 probable safety dialogs were approved by a person before the timer expired. These are `permissionDecision.source=user_temporary` accepts whose command matches the shape predicate below, 10-08 to 10-11 (13 workflow, 10 main). There were 0 human rejects. So roughly 73 dialogs were shown and about 68% expired.

**Classifier denial-limit fallback (`denialLimitFallback`): 3 inferred auto-denies, 0 since 2026-09-26.**
- The cases: 2026-09-21 (tertiary, probable), 2026-09-24 (probable) and 2026-09-26 (high confidence). They ran on 2.1.260 and 2.1.280.
- They are inferred from timing only. When the fallback expires, the model sees the exact text of an ordinary classifier denial.

**Not a timed prompt but the same unattended effect:** about 16 "Stage 2 classifier error"
denials, each arriving after a wait of 120–240 s (store reports).

## 2. Do we have a record of all of them? No

| store | rm safety, timed | rm safety, capped or immediate | fallback | tells which kind? |
|---|---|---|---|---|
| Transcripts (4 stores, incl. `subagents/**`) | **all 50** | **all 14** | needs a timing heuristic | yes for safety: deny text plus `permissionDecision.reasonType=safetyCheck` |
| Permission archive (beacon) | 26 of 48 (54%) | 0 | not separable | no; cannot tell an auto-deny from a human deny |
| Supervisor pages | 35 of 48 | 0 | not separable | no, and every page arrived after the deny |
| `~/.claude/logs/permission-denied.jsonl` | 0 | 0 | precondition only | PermissionDenied fires for classifier denials only |
| `1p_failed_events` (telemetry retry buffer) | 0 | 0 | 0 | holds only failed uploads (50 sessions, about 0.8%) |
| debug logs / OTel | 0 / off | 0 | 0 | — |

The transcripts are complete for safety-check auto-denies. They miss three things:
- **Human-answered dialogs.** The tool simply runs. `source:user_temporary` is recorded with no reason, so these can only be estimated by shape.
- **Fallback timeouts.** Their text matches a normal classifier denial.
- **Anything older than transcript retention.**

The authoritative events (`tengu_safety_check_dialog_auto_denied`, `_capped`,
`tengu_auto_mode_denial_dialog_auto_denied`, `tengu_auto_mode_denial_limit_exceeded`) exist only
in Anthropic-side telemetry.

## 3. Root causes (the 64 safety-check denials)

| # | group | n | kind |
|---|---|---|---|
| G1 | `bash -c`/`sh -c` script the check cannot read, with **no rm in it** | 40 (34 timed, 5 capped, 1 immediate) | analyzer false positive (2.1.293 inline-shell branch) |
| G2 | `cd X; rm -f rel/*` (relative glob after cd) | 12 (7 timed, 3 capped, 2 immediate) | real shape, rewritable |
| G3 | unguarded variable target, e.g. `rm -f $D/*.jpg`, `"$X"/*.json`, `rmdir $d` | 8 (5 timed, 3 capped) | real shape; 2 are false positives (rm text inside a python heredoc and inside a grep pattern) |
| G4 | `bash -c` script that does contain rm | 3 timed | real shape |
| G5 | `bash -c 'rm -f ""'` probe, flagged as removing the workspace directory | 1 timed | probe |
| F1 | classifier denial-limit fallback | 3 | classifier streaks: `cc-notify` by absolute path [Auto-Mode Bypass], `kitty @ launch`, a `git clone` of our own repo |

**What triggers G1.** From the binary (`nan()`, `Hin()`, `Uin()`, `h_e()`; dump in
`final/inline_shell_code.txt` and `final/nan_code.txt`), the check treats a `-c` script as
"could run rm" when it contains any of:
- an `rm`/`rmdir` word (case-insensitive);
- a brace expansion;
- a `$` at command position, which includes text that follows `)` or `}`.

It then cannot read the script when the script has any of:
- a function definition;
- a `$VAR` command word;
- `source`/`.`/`eval`/`shift`/`trap`;
- `set --`;
- `IFS`;
- positional parameters.

Top-level shapes are not affected (measured on 2.1.293):
- Top-level functions: 2,240 commands, 5 flagged, all 5 for an rm shape.
- Top-level `$cmd` words: 2,211 commands, 0 flagged.
- `bash /tmp/x.sh` script files: 430 commands, 0 flagged.
- `bash <<'EOF'`: 18 commands, 0 flagged.

**Hypothesis refuted.** The inventory suspected that `validate-bash.sh`'s subagent recipe
`D=$(mktemp -d …) … rm -rf "$D"` trips the check. It does not: 0 of the 64 involve it, and the
7 commands that contain mktemp were all flagged for an unrelated inline `-c` wrapper.

## 4. Mechanics constraints on any fix
- **Allow rules cannot clear the rm check.** It returns the safety ask before allow rules are consulted, and its own message says it "cannot be auto-allowed by permission rules".
- **A PreToolUse `allow` doesn't help either.** The check re-asks.
- **A PermissionRequest hook does run for these dialogs.** Measured: the beacon (a PermissionRequest hook) recorded 26 of them.
- **That hook can resolve the dialog.** Per the code reading, a hook `deny` or `allow` resolves the dialog before the timer starts. A hook resolution does not count toward the 3-per-session cap; only an expired timer does.
- **What the hook receives.** The PermissionRequest input carries `tool_name`, `tool_input` and `permission_suggestions` plus the session fields. It has no decision reason, so the hook must recognise the shape from the command text.

## 5. Candidates, ranked by timed prompts eliminated

### C1 — PermissionRequest instant-deny-with-recipe for the measured shapes (permissionrequest_hook)
- **Agent writes; operator registers.**
- **Measured basis:** the predicate `final/prfinal.py` (`detect2.classify` plus a `$sh -c` rule).
  - On all 64 it matches **41 of 50 timed**, 10 of 11 capped and 3 of 3 immediate.
  - Run only on commands that actually raised a Bash dialog in the 2.1.293 window (`final/prsim.py` over the beacon archive), it matched 32 dialogs. All 32 were dangerous-rm dialogs: 18 timed out and 14 were answered by a person. **0 other prompts matched**, so no validate-bash or ask-rule prompt would be hijacked.
  - For contrast, the same predicate run at PreToolUse time over all 260,433 Bash calls has 8–29% precision. That is why the deny belongs at dialog time.
- **Files the agent writes:**
  - `hooks/lib/rm_prompt_shape.py`, a port of `final/detect2.py` and `final/prfinal.py`. Its `--decide` flag reads the PermissionRequest JSON, prints the deny JSON on a match, and appends `{ts, sid, agent_id, shape, token, cmd_head}` to `~/.claude/logs/rm-prompt-preempt.jsonl`.
  - `hooks/rm-prompt-preempt.sh`:
    ```bash
    #!/bin/bash
    # PermissionRequest(Bash): answer Claude Code's built-in dangerous-rm dialog at once with a deny
    # that carries the rewrite, instead of letting its 2-minute timer deny it with nobody watching.
    # Only the measured shapes match; every other dialog passes untouched. A deny never widens
    # authority. Kill switch CC_RM_PREEMPT=off; CC_RM_PREEMPT=agents limits it to subagents.
    [ "${CC_RM_PREEMPT:-on}" = off ] && exit 0
    in="$(cat)"
    [ "$(jq -r '.tool_name // empty' <<<"$in" 2>/dev/null)" = Bash ] || exit 0
    if [ "${CC_RM_PREEMPT:-on}" = agents ] && [ -z "$(jq -r '.agent_id // empty' <<<"$in")" ]; then exit 0; fi
    cmd="$(jq -r '.tool_input.command // empty' <<<"$in")"
    case "$cmd" in *' -c'*|*rm*) ;; *) exit 0 ;; esac   # fork-free prefilter
    printf '%s' "$in" | python3 -I "$HOME/.claude/hooks/lib/rm_prompt_shape.py" --decide 2>/dev/null
    exit 0
    ```
- **Deny messages**, set as `decision.message` with `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":…}}}`. Each one says "Nothing ran":
  - **inline_shell:** "Claude Code's built-in removal check cannot read this `bash -c` script (a function, a \"$@\" runner, a $VAR used as a command, source/eval, set -- or {a,b}), so it would hold a 2-minute prompt and then deny it. Nothing ran. Re-issue it without the -c wrapper: run the statements directly in this Bash call, or Write the script to a file and run `bash /tmp/<name>.sh` (`timeout N bash /tmp/<name>.sh` for a bound). A script file is not a way around the check: inside it, every rm target must be a literal absolute path or \"${VAR:?}\"-guarded."
  - **unguarded_var:** "The rm target `<tok>` is a variable followed by a slash; if the variable is empty it becomes / or /*, so Claude Code's removal check would prompt for 2 minutes and then deny. Nothing ran. Re-run with \"${VAR:?}\"/… or the literal absolute path. If the variable came from cd, pwd, dirname or git rev-parse, only a literal path passes."
  - **cd_rel_glob:** "This command changes directory and then removes the relative glob `<tok>`, which Claude Code's removal check cannot resolve, so it would prompt for 2 minutes and then deny. Nothing ran. Re-run with the absolute path: `rm -f /abs/dir/<glob>`."
- **Tests:** `tests/rm-prompt-preempt.bats`.
  - Positives: the 54 predicate-hit commands in `final/autodeny-64.tsv`.
  - Negatives that must pass through silently:
    - a literal-absolute-path workspace removal (a real removal must still reach the person);
    - `R=/tmp/x; rm -rf $R` (validate-bash's own ask);
    - `git rm -r --cached $P`;
    - a non-Bash tool;
    - `CC_RM_PREEMPT=off`.
- **Registration:** `migrations/NNNN-rm-prompt-preempt-registration.sh`, class `c10`, cloned from `migrations/0047-read-before-write-parity-registration.sh`. It appends its own group, `{"matcher":"Bash","hooks":[{"type":"command","command":"~/.claude/hooks/rm-prompt-preempt.sh","timeout":10}]}`, to `.hooks.PermissionRequest`. Its verify line is `jq -e '[.hooks.PermissionRequest[]?|select(.matcher=="Bash")|.hooks[]?.command]|any(.=="~/.claude/hooks/rm-prompt-preempt.sh")' ~/.claude/settings.json`. The operator runs `scripts/c10-batch.sh --confirm settings.json`.
- **Companion changes** (agent, same diff), so a preempted dialog does not page:
  - `scripts/lead-supervisor.sh`, near :1148: drop a pending beacon whose `tool_input.command` matches `rm_prompt_shape.py`.
  - `hooks/notify.sh permission`: skip the notification on a match.
  - Both are gated on the hook being registered.
- **Acceptance probe, before registering fleet-wide.** The claim that a hook deny resolves the dialog before its timer comes from reading the code. Prove it once:
  - Fire a session with a `--settings` overlay that registers only this hook.
  - Run `bash -c 'f(){ "$@"; }; f true'` in it.
  - Expect the hook's deny text within 5 s rather than at 120 s.
  - Use no slash commands in the probe.

### C2 — Shell-shape rule in the worker agent definitions (model_guidance; agent writes)
`agents/workflow-lean.md` is the system prompt for 42 of the 64 hits. Workers of that type never
see CLAUDE.md, so this file is the only text that reaches them. Append it under "Tool behaviour",
and add the same bullet to `agents/deep-research.md` (3 hits):
> - Claude Code's built-in removal check holds a 2-minute prompt and then **denies** the call when nobody answers; no allow rule or hook can approve it. Keep commands readable to it. (1) No `bash -c '…'`/`sh -c '…'` around a function, a `"$@"` runner, a `$VAR` used as a command, `source`/`eval`, `set --` or `{a,b}`, even with no rm in it: run the statements directly in the Bash call, or Write the script to a file and run `bash /tmp/<name>.sh`. (2) Every rm/rmdir target is a literal absolute path or `"${VAR:?}"`-guarded, never `$D/*` or `"$D"/*`. (3) Never `cd X; rm rel/*`; write `rm -f /abs/X/rel/*`. A script file is not a way around (2) or (3).

Up to 45 prompts (estimated; compliance not measured). It also reaches the 3 immediate and 11 capped denials, which C1 cannot.

### C3 — The same rule for main sessions and default workflow subagents (model_guidance; agent writes)
These contexts load CLAUDE.md: 10 main sessions and 8 `workflow-subagent` hits.
- **`CLAUDE.global.slim.md`, § Working rules**, one bullet:
  > - Claude Code's built-in removal check prompts for 2 minutes and then denies when nobody answers; no allow rule clears it. Keep commands readable to it: no `bash -c '…'` wrapper around functions, `"$@"` runners, `$VAR` commands, `source`/`eval` or `set --` (run the statements directly, or write a script file and run `bash <file>`); give rm a literal absolute path or `"${VAR:?}"`; never `cd X; rm rel/*`.
- **`skills/agent-browser/SKILL.md`** (9 of the 64 involve agent-browser):
  > Bind the session as a top-level function, `AB(){ agent-browser --session <name> "$@"; }`, never `AB="agent-browser …"; $AB …` inside `bash -c`. Clear a screenshot dir with `rm -f /abs/dir/*.jpg` or `rm -f "${D:?}"/*.jpg`.

Up to 18 prompts (estimated). Run the instruction-budget gate after the edit.

### C4 — Durable local record (telemetry_capture; agent writes)
- **`bin/cc-autodeny-census`.** A read-only port of `final/scan.py`, `final/classify.py` and `final/corpus.py`.
  - It runs `rg -l` for the deny marker and `"reasonType":"safetyCheck"` over the 4 stores (about 9 s), parses only the hit files, and deduplicates by tool_use_id.
  - It classifies each row by outcome, cause, context, agent type and version.
  - It adds two inferred rows:
    - **Fallback timeout:** a classifier denial at least 120 s after its tool_use, preceded by at least 2 consecutive classifier denials in the same transcript.
    - **Probable answered safety dialog:** a `user_temporary` accept whose command matches the predicate.
  - It appends new rows to `~/.claude/logs/autodeny.jsonl`, idempotently.
- **Run it weekly.** Add one step to `skills/permission-harvest/SKILL.md`: `cc-autodeny-census --since 7d`.
- **C1's own log.** `rm-prompt-preempt.jsonl` records every dialog C1 resolves.
- **Optional: key beacons per agent.** Change `hooks/cc-permission-beacon.sh` to use `$SID${AGENT_ID:+.$AGENT_ID}.json`. Parallel subagents currently overwrite one beacon, which is why the archive holds only 54%. Caveat: the main session's Stop clears are unconditional today, so this needs its own tests.

### C5 — Narrow allow rules for the classifier-fallback path (allow_rule; operator, via permission-harvest)
These are spellings of tools that are already allowed or read-only. The prefix rule `Bash(cc-notify:*)`
misses absolute paths, which is the "allow rule is a prefix" lesson.
- **The rules:** `Bash(~/.claude/bin/cc-notify:*)`, `Bash(/Users/chrisren/.claude/bin/cc-notify:*)`, `Bash(~/Development/claude-infrastructure/bin/cc-notify:*)`, `Bash(bash ~/.claude/scripts/wrap-ledger.sh:*)` and `Bash(~/.claude/scripts/wrap-ledger.sh:*)`.
- **Why wrap-ledger is safe to allow:** it is pure-read, its header says so, and it writes only a memo cache. It went to the classifier 59 times in this window, and once it was denied after a 242 s stage-2 error.
- **Impact:** about 1–3 fallback prompts over 6 weeks, plus less exposure to classifier stalls.
- **Alternative with no settings change:** a C3 clause telling sessions to invoke in-house tools by their bare PATH name.

### C6 — `CLAUDE_CODE_DISABLE_INLINE_SHELL_RM_PROMPT=1` (env_or_flag; operator only; not recommended)
- **Effect:** removes all 43 inline-shell denials (G1 + G4) at once.
- **Risk:** it switches off CC's only look inside unreadable `-c` scripts, including the 3 that really contain rm.
- **When to use it:** only if C1 is rejected.

## 6. Rejected alternatives (measured)
- **PreToolUse deny in validate-bash.sh:**
  - Precision is 5–8% over all 260,433 Bash calls since 2.1.284, or 29% on 2.1.293 inline-shell commands (`final/detect.py`, `detect2.py`, `feat.py`).
  - The cause: CC resolves literal assignments and single `cd … &&` chains, which a regex cannot replicate, and its parser changes every release.
- **PreToolUse rewrite to `${VAR:?}`:** it would also rewrite rm text inside heredocs and grep patterns, which are data. 2 of the 8 G3 hits are exactly that.
- **PermissionRequest auto-allow for inline scripts with no rm:** it would bypass both CC's check and the auto-mode classifier. The deny-with-recipe in C1 gets the same benefit at the cost of one retry turn.
- **`CLAUDE_CODE_DISABLE_DANGEROUS_RM_TIMEOUT`:** it never allows. In auto mode it routes to the classifier (inferred), in bypass mode it gives an untimed prompt, and headless runs deny.

## 7. Evidence files
- **The 64 deduplicated denials:** `final/autodeny-64.tsv`, with per-row predicate hits.
- **Scan and classification:** `final/hits.json`, `final/rows.json`.
- **The 260,433-call corpus:** `final/corpus.json`.
- **Predicates and how they were scored:** `final/detect2.py`, `final/prfinal.py`, `final/prsim.py`.
- **Binary excerpts:** `final/inline_shell_code.txt`, `final/nan_code.txt`.
- **Earlier phases:** `mechanics.md`, `local-telemetry.md`, `inventory.md`, and the per-store TSVs `_claude*_projects.tsv`.
