# Permission-config inventory for timed auto-deny prompts (repo wt-cc-174746-13116 @ b63879a7d)

All counts were measured by reading the files with python/jq/grep. Paths without a prefix are relative to the repo root.

## 1. Where the rules live

- **Live file:** `~/.claude/settings.json` is a regular file (44,547 B). `~/.claude-{secondary,tertiary,quaternary}/settings.json` are symlinks to it, so all four accounts share one file.
  - None of the account dirs has a `settings.local.json`.
  - `permissions` (measured): allow=361, deny=41, ask=3, `defaultMode:"auto"` (line 435). `skipAutoPermissionPrompt:true` (line 1292).
- **Template:** `settings-templates/settings.example.json` has allow=17, deny=41, ask=6 (lines 91-98).
  - The template `ask` list adds `git restore`, `git stash drop` and `git reset --hard`. These are absent from the live file, whose `ask` list is `fly deploy:*`, `git push:*` and `git stash clear:*`.
- **install.sh:1392-1440:**
  - With `--wire-hooks`, or on a fresh dir, it merges the template hooks and unions `deny`/`ask`.
  - `allow` is "DELIBERATELY NOT unioned" (line 1440). Line 1408 says: "Merging settings.json is the OPERATOR's hand via this installer — never an agent Write; the C10 ceiling holds."
- **Project files:**
  - `.claude/settings.json` holds 37 allows and no rm rules.
  - `.claude/settings.local.json` holds `Bash(rm -rf bin/__pycache__)`, `Bash(rm -fr bin/__pycache__)` and `Bash(rm -rf scripts/__pycache__)` (lines 9-11), `Bash(git worktree add|remove|list|prune:*)` (lines 23-26) and `Bash(bash scripts/worktree-gc-infra-run.sh)` (line 94).
  - Across all `~/Development/*/.claude/settings*.json` (56 files, found with `find -maxdepth 4`): 23 rm/rmdir/worktree allows, 4 denies, 2 asks. Examples:
    - finance-ai-web-app: `allow Bash(rm:*)`, `ask Bash(rm -rf:*)`, `ask Bash(rm -r:*)`.
    - reso-management-app: `allow Bash(rm -rf .next)`, `allow Bash(rm -rf coverage)`.
    - doc_classifier: `allow Bash(rm -rf artifacts)`, `allow Bash(rm -f .teammate-busy)`.
    - reso-management-app, reso-management-app-release and reso-qa-runner: `allow Bash(git worktree remove:*)`.
- **rm, worktree and cleanup deny rules, live and template:**
  - Live file lines 398 and 404-416: `Bash(git clean:*)`, `Bash(rm -fr /)`, `Bash(rm -rf $HOME)`, `Bash(rm -rf $HOME/)`, `Bash(rm -rf .git)`, `Bash(rm -rf .git/)`, `Bash(rm -rf /)`, `Bash(rm -rf /*)`, `Bash(rm -rf ~)`, `Bash(rm -rf ~/)`, `Bash(unlink:*)`.
  - Live file also denies `shred:*`, `truncate:*` and `dd:*`.
  - The same set is in the template at lines 60 and 76-89.
  - There is no global `Bash(rm:*)` allow or ask. The global allow list does include `Bash(find:*)` (line 129).
- **autoMode** (lines 1293-1340). It has only `soft_deny` (35 entries) and `environment` (8 entries). There is no `autoMode.allow` and no `"$defaults"` in either list (`grep -c '$defaults'` = 0).
  - Migration `0046-automode-environment-defaults.sh` (c10) would prepend `$defaults` to `environment`. It is staged and not live.
  - rm-relevant `soft_deny` prose:
    - #13 (line 1308): "Irreversible Local Destruction: Irreversibly deleting, truncating, or overwriting local files that existed before the session started without explicit user direction naming the specific targets."
    - #6: "Logging/Audit Tampering: … deleting log directories, removing git hooks …"
    - #23 (line 1318): "Self-Modification: … UNLESS the operator directed that change in the conversation (standing ruling 2026-10-01: 'we have the autonomy and agency to modify our own permissions and settings files')."
  - `environment` #4 (line 1336): kitty panes are "the operator's own local Claude Code sessions … the agent reads, types into, submits, recycles, hands off and closes them (kitten @, handoff-fire.sh, cc-await-ping, git worktree housekeeping) with no human in the loop."
- **Env:** the live `env` sets none of `CLAUDE_CODE_DISABLE_DANGEROUS_RM_TIMEOUT`, `CLAUDE_CODE_DISABLE_SUBSTITUTION_RM_PROMPT` or `CLAUDE_CODE_DISABLE_INLINE_SHELL_RM_PROMPT`. All three exist in the 2.1.293 binary.

## 2. Hooks that act before the dialog

PreToolUse(Bash) runs in this order (live settings.json:736ff): `smart-bash-allowlist.sh`, `curl-gate-scope.sh`, `validate-bash.sh`, `git-worktree-guard.sh`, `keychain-guard.sh`, `rm-safe-allowlist.sh`, `ship-rail-push-allow.sh`, `qos-rewrite.sh`, `coldcompile-admit.sh`, `pr-gate.sh`. The deployed hooks link to `~/Development/claude-infrastructure`; `cmp` shows them identical to this worktree for all five rm/worktree hooks.

- **`hooks/rm-safe-allowlist.sh` (146 lines):**
  - It allows only a simple, single `rm` (line 63 bails on `; & | $( \` > <` and newline).
  - Flags must match `^-[rfRdvi]+$` or be `--recursive|--force|--verbose|--dir` (lines 122-125).
  - Every target must be either:
    - a regenerable name component from SAFE_NAMES (line 70: node_modules, .next, dist, build, out, target, `__pycache__`, the various caches, coverage, test-results, playwright-report, artifacts, .terraform, …), or
    - `tmp/<sub>` (line 109), or an absolute `/tmp/?*` or `/private/tmp/?*` (lines 86-88).
  - It rejects globs, `~` and `..` (line 79) and any `.git` component (line 99).
  - Output is a PreToolUse `permissionDecision:"allow"` (lines 137-145). Kill switch: `RM_SAFE_ALLOWLIST_DISABLED`.
- **`hooks/lib/smart-bash-allowlist.py:950-963`:** for an `rm` inside a compound command, it runs rm-safe-allowlist.sh on that one segment (`_rm_hook_allows`, lines 597-630). It leaves a sole `rm` to rm-safe.
- **`hooks/validate-bash.sh` (2306 lines):**
  - `warn()` (line 163) emits `ask`; `deny()` is at line 149.
  - `sudo rm` and fork bomb: deny (line 821).
  - Catastrophic recursive+force rm on root or home: argv-based deny (lines 852-879).
  - Recursive rm on a target that is not permitted goes through `rm_recursive_refuse` (lines 2243-2254):
    - In a **subagent** it is a **deny** with mktemp guidance (line 2251; kill switch `CC_VB_AGENT_RM_DENY=off`).
    - Otherwise it is `ask "rm -r on non-build-artifact target"` (line 2253).
  - Permitted targets: `SAFE_RM_TARGETS` (line 1942), the session scratchpad category (lines 1944ff, decided on the resolved path) and a self-created `T=$(mktemp -d) … rm -rf "$T"` category (lines 2131ff). The comment there says that case was "165 of the 721" rm asks in 30 days.
  - It explicitly does NOT widen to literal /tmp paths, because of live infrastructure such as `/tmp/cc-daemon-501`.
  - Lines 1543-1616 deny any argv that carries both `cc-permission-harvest` and `--apply`.
- **`hooks/git-worktree-guard.sh`:** exits 2 (block) on `git worktree remove` when a live claude has its cwd in the tree or lsof shows open files, and on `git branch -d|-D` of a branch with a worktree (header lines 10-15). Kill switch: `WT_GUARD_DISABLED`.
- **PermissionRequest hooks** (live lines 629ff): `notify.sh permission|question|plan`, `cc-permission-beacon.sh write` (writes `/tmp/cc-permission-pending/<sid>.json` and archives to `~/.claude/autonomy/permission-archive`), and `workflow-script-edit-allow.sh` (Write|Edit only). No PermissionRequest hook decides Bash.
  - **PermissionDenied:** `permission-denied.sh` logs to `~/.claude/logs/permission-denied.jsonl` and writes nothing to stdout.
- **`hooks/model-permission-decider.py`** is a **PreToolUse** hook, not a PermissionRequest hook, and it is **not registered anywhere**. `docs/plans/GUARDRAIL_HOOKS_V2.md:355` says "unregistered everywhere"; migration `0022-mitl-decider-shadow.sh` would add it in shadow mode.
  - It can only emit `allow` or `ask`, and `deny` is unreachable (docstring lines 11-15; `emit()` line 464).
  - It fences `ask`/`deny` live from settings (lines 163-185, 211). It consults a haiku `claude -p` child and fails to `ask`. The default `MITL_MODE` is shadow (line 511).
- **Nothing rewrites rm commands.** `qos-rewrite.sh` is the only rewriter, and it is not rm-related.

### From the binary (`/tmp/cc293-strings.txt`, minified code read with python; this is inference, not a measured test)

- The timed window comes from `wln(...)`. It is reached only when the decisionReason carries a breaker with `autoModeDeny:true`, and the only such breaker is **`dangerousRemoval`** (`{bypassImmune:!0, classifierRouted:!0, autoModeDeny:!0}`).
- The window is also gated on `LLe(mode)` (auto) and on `!Vt`, where `Vt = rG(ke)` means "an `ask` permission RULE matched".
  - So a matching `permissions.ask` rule appears to divert a dangerous-rm into the ordinary **untimed** prompt.
  - Possible lever: a narrow `ask` rule, such as the `ask Bash(rm -rf:*)` already in finance-ai-web-app. **This needs a live test.**
- The binary's messages say the removal "requires explicit approval and cannot be auto-allowed by permission rules": `Dangerous rm operation detected: the target is the output of a command substitution`, and `removal target cannot be statically resolved`. So allow rules cannot clear it.
- Whether a PreToolUse hook `allow` clears it is unverified. `bypassImmune` suggests not.
- **Implication:** validate-bash's mktemp and scratchpad permits for `rm -rf "$T"` and `"$D"` stop the hook's own ask, but CC's built-in check still sees an unresolvable `$VAR` and raises the timed dialog.

## 3. The sanctioned change workflow

- **`skills/permission-harvest/SKILL.md`** (also at `~/.claude/skills/permission-harvest`):
  - It "runs cc-permission-harvest read-only … proposes composable prefix allow rules and hands the operator one apply line. Never writes settings files" (line 3).
  - The rm heads are **HOOK_OWNED** (line 75): "`rm`/`rmdir` → validate-bash.sh's rm guard and rm-safe-allowlist.sh … Proposing it claims a clearance that cannot happen". `Bash(rm:*)` is refused on purpose by ASK_DENY_COLLISION (line 77).
  - The hand-over (lines 133-164) is exactly: `env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_ENTRYPOINT CONFIRM=1 ~/.claude/bin/cc-permission-harvest --apply`.
  - §6 NEVER (lines 166-182) says: never run `--apply` in-session; never edit `settings.json` or `settings.local.json` by hand in any config dir.
- **`bin/cc-permission-harvest`** (2996 lines): read-only report, plus `--json --out`, `--check` and `--falsify`. `--apply` is for the operator only and is denied by validate-bash.
- **`bin/cc-permission-audit`** (432 lines): ranks unmatched Bash commands and reads the beacon archive. `--prune` is a dry run by default and writes only with `CONFIRM=1`. `CLAUDE.global.slim.md:201` says reading permission state is the agent's job and applying changes is the operator's.
- **`scripts/permission-gate-lint.sh`:** a ratchet on unbounded deploy and land gates. **It is unrelated to CC permission rules.**
- **Migrations:** a settings change is authored as a `migration-class: c10` file in `migrations/`, which is "staged, never run" (migrations/README.md:70-77). The operator runs `bash scripts/c10-batch.sh --confirm settings.json` (README:129-136). Examples: 0046, 0054-automode-land-allow.
- **`CLAUDE.global.slim.md:200`**, which is byte-identical to the deployed `~/.claude/CLAUDE.md`: "A file you hand over contains no permission grants, no settings*.json or allowlist edits… Ask for a permission in chat, as its own request."
- **Agent may edit:** hook code in the repo (validate-bash.sh, rm-safe-allowlist.sh, smart-bash-allowlist.py, with their bats tests), harvest proposals, and new c10 migration files.
- **Operator only:** any write to `~/.claude/settings.json`, project `settings*.json`, `env` flags such as `CLAUDE_CODE_DISABLE_DANGEROUS_RM_TIMEOUT`, `--apply`, and `c10-batch --confirm`.
- **Tension to flag:** soft_deny #23 cites a 2026-10-01 standing ruling allowing self-modification of settings. That conflicts with SKILL §6 and CLAUDE.global.slim.md:200. No other repo file contains the ruling text (`rg 'autonomy and agency'` finds nothing).
- **Docs:** `rg` over docs/hooks/scripts/bin/skills finds **0 hits** for "auto-deny", "automatically deny", "splendid_horizon", "autoDenyWindow", "DANGEROUS_RM_TIMEOUT", "dangerousRemoval", "Dangerous rm operation", "denial limit" and "built-in Claude Code safety check". This mechanism is not documented in the repo. Related existing research: `docs/research/permission-prompt-census-2026-09-10.md`, `permission-matcher-truth-2026-08-20.md` and `hook-ask-confirmations-2026-09-28.md`.

## 4. Existing guidance to the model about rm

- `.claude/rules/agent-operating-lessons.md:43`: a subagent or an unattended fired session cannot answer an ask, so briefs must "ban them BY NAME (heredoc edits, git stash, rm -r, git reset --hard)" (see docs/lessons/a-subagent-cannot-answer-a-permission-prompt-so-a-prompt-trigger.md).
- `.claude/rules/agent-operating-lessons-situational.md:89`: an allow rule cannot silence a hook's ask; "the lever is the HOOK".
- validate-bash.sh:2251 gives subagents this deny text: use `D=$(mktemp -d /tmp/<name>.XXXXXX) … rm -rf "$D"`. **That is exactly the unresolvable-`$VAR` shape CC's dangerousRemoval check prompts on**, so the guidance may be what produces the timed prompts.
- `CLAUDE.global.slim.md:27`: a refusal is an answer, so do not re-issue it reworded.
- The deployed CLAUDE.md has no rm, trash or mktemp rule (`grep` finds none). `/usr/bin/trash` exists but no guidance uses it. There is no safe-rm wrapper.
- Cleanup helpers: `scripts/scratchpad-reaper.sh`, `worktree-gc.sh`, `worktree-gc-infra-run.sh`, `cc-gc.sh`, `branch-reaper.sh`, `team-orphan-reaper.sh` and `bin/cc-reaper`, plus `templates/safe-disk-cleanup/tmp-roots.list`.
