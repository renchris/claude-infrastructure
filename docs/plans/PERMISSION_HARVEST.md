---
status: in-progress
created: 2026-09-08
owner: permission-harvest worktree
---
# PERMISSION_HARVEST — the recurring loop from manual permission prompts to composable allow rules

**Created:** 2026-09-08 · **Operator ask (verbatim):** *"create the 100th percentile absolute perfection
implementation of a skill that we can run on a regular basis (perhaps on weekly cron?) that takes our
accumulated manual permission prompts towards improving allowlist of scalable and composible allowed
command patterns."* · **Worktree:** `~/Development/.worktrees/wt-permission-harvest` (branch
`permission-harvest`) · **Frozen DoD:** `~/.claude/autonomy/dod/repo-86523465733a9afe.md`.

`Scope (frozen):` build the permission-harvest loop — a shared matcher library, a harvester CLI with
deterministic refutation gates and an operator-run apply, a skill, a weekly launchd job wired the way
this repo wires jobs (manifest row + c10 migration + activation script), bats suites, and this plan.
Never write permission config from an agent session; apply is operator-run via `cc-do`.

---

## Phase 0 — Orchestration

**Execution locus per wave:** **W · Dynamic Workflow agents** (operator directive in the `/goal`:
*"ultracode Dynamic Workflow"*). W is locus **T** with two differences that keep the lead's window
protected: every agent's return is schema-bounded (≤ a few hundred tokens) and its real product is a
FILE in the worktree, and the workflow runs in the background so no report lands in the lead's context
unasked. Lead-inline (**L**) only for this plan and the final commits.

**Task size band:** every implementation unit written to **40–150K output tokens ≈ 3–6 files ≈ one
task**. Units below are sized to that; none bundles two tasks.

**Waves and units:**

| Wave | Unit | Writes (all under the worktree) | blockedBy |
|---|---|---|---|
| A · Profile | A1 archive ceiling · A2 acceptance census · A3 wiring facts | `docs/research/permission-harvest-profile-2026-09-08.md` (A1+A2), plan § Wiring facts (A3, via lead) | — |
| B · Critique | B1 widening/security · B2 measurement fidelity · B3 operational inertness | findings only → folded into this plan by the lead | A (barrier: critics need the numbers) |
| C · Implement | C1 matcher lib + fidelity suite · C2 harvester CLI · C3 launchd/wrapper/migration/activation · C4 skill + doc cross-links · C5 harvester bats + fixtures | see § File map | C2 blockedBy C1 (imports its API); C3/C4/C5 independent |
| D · Verify | D1 run every suite + repo lints, fix loop · D2 three adversarial reviewers over the diff · D3 completeness critic vs the frozen DoD | fixes in place | C |
| E · Land | lead: atomic commits per unit, project `/ship`, `deploy-live` converge, close | — | D |

**Lead context budget:** ≥50% of the window reserved for deciding. **Succession point:** if the lead
passes ~65% fill before wave D completes, `handoff-fire.sh --recycle --worktree permission-harvest`
with this plan as the brief — everything of value is on disk (this plan, the DoD, the worktree).

**Worktree discipline:** ONE worktree, disjoint files per unit, no agent creates worktrees. The
shared checkout `~/Development/claude-infrastructure` is never written (`.claude/CLAUDE.md`).

---

## 1. Why this loop, and why it was not built before

`docs/research/permission-prompts-2026-08-23.md` §3 is the negative result that shaped this design:
of 1,297 non-curl prompts 97% were compound and only 3% a simple command a prefix rule could cover;
nine of nine allowlist proposals derived from `bash-commands.log` were refuted by an adversarial
verifier (counts inflated 2×–174×, two would have granted arbitrary code execution). The lever that
actually cut prompts was fixing two hooks (`curl-gate.py`, `validate-bash.sh`).

Two facts landed since then change what is buildable — both from
`docs/research/permission-matcher-truth-2026-08-20.md`:

1. **Compound commands ARE decomposed** by the harness (`MT` splits on `&& || ; | |& & \n` and loops /
   conditionals; every leaf must match an allow rule independently). So the unit a rule covers is the
   **leaf sub-command**, and a small set of leaf prefixes composes across every compound command that
   chains them. That is the composability the operator asked for, stated in the matcher's own terms.
2. **Only `bashMissKind: no-rule-match` is fixable by a rule.** `$( )`, backticks, subshells, `{ }`,
   a trailing `&`, redirection to a file, heredocs, `bash -c`, >10,000 chars, multiple `cd`, and
   `cd`+`git` in one line are **structural** — no allow rule of any form clears them. A harvester
   that does not partition on this first will re-inflate every count the 2026-08-23 verifier refuted.

So the design is: **partition structural from allowlistable · decompose to leaves · set-cover the
uncovered leaves into prefix rules · refute every candidate deterministically against the oracle
before proposing it · consolidate the operator's own exact acceptances into the prefixes that shadow
them · hand the apply to the operator as one `cc-do` step.** Counts come from the beacon archive
(the oracle of prompts that actually happened), never from the command log, which is used for
exactly one thing — measuring what a candidate would NEWLY admit.

---

## 2. Evidence stores (inputs)

| Store | Role here | Notes |
|---|---|---|
| `~/.claude/autonomy/permission-archive/*.jsonl` | **THE ORACLE** — 3,838 resolved prompts (3,719 Bash), 2026-07-31 → | written by `hooks/cc-permission-beacon.sh`; per-row `tool_input.command`, `waited_s`, `resolved_by`, `tool_sig`/`cleared_tool_sig`, `cwd`. Classification `approved · refused · collateral · unknown` is PROVEN by signature, never inferred (`_classify` in `bin/cc-permission-audit`, moving to the shared lib) |
| `~/.claude*/settings.json` (5 forks, 339/339/338/338/338 allow entries, 5 md5s) | the fleet allow/deny/ask in force; the **apply target** | forked; the config mirror does not heal it — apply writes all five or it silently applies to one account |
| `~/Development/**/.claude/settings.local.json` (52 project + 87 worktree copies) + `.claude/settings.json` | **manual acceptances rendered as rules** — "yes, don't ask again" writes up to 5 exact rules per compound (F19), one per unapproved leaf; **the consolidation denominator and its apply target** | A2 2026-09-08: 975 exact acceptances in project files (956 distinct literals, 67 % path-bound); worktree files are evidence, never targets. *(The 2026-08-12 figures — 2,036 distinct, 48 % exact, 359 absolute paths — are stale.)* |
| `~/.claude/logs/bash-commands.log` (+5 `.gz` rotations, 286,466 anchored RECORDS / 1.6 M lines) | the **widening receipt** only — what a candidate newly admits | a **post-hook pass-through record**: written at `validate-bash.sh:1341` after every deny/warn path has exited, so it is pre-scrubbed of everything a danger regex would look for (§10 B1-3); never a prompt count |
| `~/.reso/curl-audit.jsonl` · `~/.claude/logs/validate-bash-decisions.jsonl` (new) | **hook attribution** — a row joined (session_id, ±15 s) to a hook `ask` is `hook_raised`, never a rule gap | 1,367 of 1,368 curl-only "gap" rows joined (A1) |
| session transcripts `~/.claude*/projects/<slug>/{<sid>.jsonl,<sid>/**/*.jsonl}` | the **denial oracle** — `tool_result` "doesn't want to proceed" for the prompted `tool_use` | ~19 genuine denials hide in `collateral`; subagent files hold most of them (B1-6) |

The rules in force for a given archived prompt are the UNION (§5 of the matcher doc) of the fleet
file and the `.claude/settings*.json` reachable from the prompt's `cwd`. The simulator resolves that
per row so a project-local rule is not mistaken for a fleet gap.

---

## 3. Design — `bin/cc-permission-harvest`

### 3.1 Pipeline

1. **Load** rule sets — fleet union + per-cwd local, **filtered by mode** (`mode='auto'`, the fleet's
   measured `defaultMode`: allow rules `auto_mode_dropped` drops are NOT in force; report
   `covered_auto` vs `covered_default`) — archive rows in the window, and the corpus parsed by
   anchored RECORD (`^\[ISO Z\] \[sid\] `), `.gz` rotations included (82 % of its LINES are
   continuation fragments; §10 B2-2). Tag each row `local_rules: recovered|unrecoverable` (40.9 % of
   rows have a cwd that no longer exists); unrecoverable rows use the UNION of all discovered
   project-local allow rules (conservative) and are excluded from MIN_EVIDENCE counting.
2. **Resolve** each row: `approved | refused (Stop) | denied (transcript-confirmed rejection) |
   abandoned (SessionEnd) | collateral | unknown` (shared `classify_row` + `denial_oracle`).
3. **Structural triage** (`permission_matcher.split_leaves`): a row carrying any hard-gated construct
   → STRUCTURAL with its kind(s), reported with top verbs per kind; `unverified_kinds`
   (`function_def`, `case`) are reported separately from the headline until probed. **3b — HOOK_RAISED:**
   join each row (`session_id`, `ts ± 15 s`) to hook decision logs (`~/.reso/curl-audit.jsonl`;
   `~/.claude/logs/validate-bash-decisions.jsonl`, new) → bucket `hook_raised:<hook>`; such rows never
   feed candidates (MEASURED: 1,367 of 1,368 curl-only "gap" rows were curl-gate asks — 80 % of the
   bucket). Rows whose leaves hit an `ask`/`deny` rule → `ask_hit`/`deny_hit`; rows the beacon cut at
   `CC_PERMARCHIVE_MAXLEN` → `truncated`. Buckets are MECE and sum to `rows`.
4. **Decompose** the remainder to leaves; normalise each exactly as `iae` does; find the leaves NO
   surviving rule covers. Zero uncovered leaves → `hook_or_classifier`; else `rule_gap`.
5. **Generate candidates** from uncovered leaves at 1-, 2- and 3-token heads as `Bash(<head>:*)`.
   Worked example: `Bash(gh pr view:*)` (2 tokens, sub-verb, no exec-bearing args). `git -C <path>
   <verb>`: the `-C <path>` pair is skipped and the verb is the head; the receipt states the `-C`
   forms it will NOT cover (`iae` does not skip `-C`).
6. **Greedy set cover — ranked by distinct sessions, then rows; Σ`waited_s` is REPORTED, never
   ranked on** (it is a hang metric decided by ~20 overnight outliers). A row clears when ALL its
   uncovered leaves are covered by surviving rules ∪ picked heads. Stop when the best candidate fails
   MIN_EVIDENCE.
7. **Refute** each picked candidate through the gates in §3.2; a refused candidate is reported with
   the prompts it would have cleared so the cost of refusing it is visible, and set cover continues
   without it.
8. **Consolidate** existing EXACT entries — **a PROJECT-LOCAL operation and the loop's largest
   denominator** (A2: the five fleet files hold 0 exact entries; 975 exact acceptances live in
   `~/Development/*/.claude/settings.local.json`, 67 % path-bound; ceiling at `--min-cluster 2` ≈ 58
   prefixes retiring 254 entries). Per file: group exact entries by **2-token sub-verb head**; a
   cluster of ≥ `--min-cluster` entries proposes `Bash(<head>:*)` INTO THAT FILE, through every gate
   in §3.2 (PATH_BOUND in project scope). Never mint a consolidation prefix for
   `rm mv cp chmod chown chflags ln dd truncate install` from path-bound literals. Entries a proposed
   or existing prefix shadows (`dead_entries`) are listed as prunable. The three dominant
   UNRETIRABLE clusters (`ssh -i` ×181 in cloud-agent — AUTO_MODE_DROP; `perl -ne` ×82 — ACE;
   `git -C <path>` ×82 — un-normalisable) are reported by file as residue, so the ~60 % that no
   gate-passing prefix can retire is visible rather than silently absent.
9. **Emit** the report (default) and the JSON proposal (`--json`, `--out DIR` →
   `proposal-<UTC>.json` + `latest.json`, a COPY). Exit 0 even when 0 rules are proposed (an explicit
   `proposed=0` line carrying its denominator `rows_in_window`/`oracle_age_s` — never the error
   channel for a null result). Exit 3 when BLIND: archive absent / unreadable / partly unreadable /
   **oracle-dark** (`.archive-alive` older than `CC_PERMHARVEST_ORACLE_MAX_AGE_S` = 259200, or
   `rows_in_window == 0` while files exist) — a dead beacon must never read as a healthy
   `proposed=0` (§10 B3-3).

### 3.2 Refutation gates (deterministic; every candidate carries every gate's verdict + reason code)

*Revised after wave B (2026-09-08) — the original 8-gate table is preserved in §10 with the reason each
row changed. Eleven gates now; `DANGER_WIDENING` is deleted (its denominator was pre-filtered by its own
predicate, §10 B1-3) and widening is a RECEIPT, not a gate.*

| Code | Refuses when | Why |
|---|---|---|
| `ACE_CLASS` | head verb ∈ interpreters / shells / exec wrappers / env runners / PERSISTENCE+LAUNCH verbs: `bash sh zsh fish dash ksh python* node deno bun tsx ruby perl php lua eval exec env xargs sudo source . npx bunx pnpx docker devbox mise direnv watch setsid ionice flock nohup timeout awk` + `launchctl defaults crontab at osascript automator open security export set` + `find` (its `-exec/-execdir/-ok/-delete` cannot be pinned past) | the rule approves whatever follows (F12/F13) or installs something that runs later; the 2026-08-23 `Bash(bash:*)`/`Bash(python3:*)` refutation made mechanical |
| `ARG_EXEC` | the head's verb has an exec-bearing ARGUMENT the head's own tokens do not pin past — static table: `git` (`rebase -x/--exec`, `bisect run`, `filter-branch`, `submodule foreach`, `difftool/mergetool --extcmd/--tool-cmd`, global `-c`), `tar -I/--use-compress-program`, `rsync -e`, `ssh/scp -o ProxyCommand`, `sort --compress-program`, `find -exec…`, `xargs` | MEASURED: `git rebase -x 'touch MARK' --root` executes; a prefix rule is a grant over arguments not yet typed. `Bash(git rebase:*)` — the plan's former worked example — fails here; `Bash(git rebase --abort:*)` (3 tokens) passes |
| `FLAG_HEAD` | the head's LAST token starts with `-` | `rm -f`, `rm -r`, `sed -n`, `curl -sS` are the bare verb in disguise; the head inherits every verdict of its verb-only head (ACE, collision, ARG_EXEC) |
| `SHELL_KEYWORD` | head ∈ `do done then fi else elif for while until if [ [[ # set export case esac function select time` | F19's splitter saves loop/test leaves as exact rules — 73 such acceptances exist; `Bash(do:*)` is nonsense that passes every other gate |
| `HOOK_OWNED` | a shipped PreToolUse hook owns the head's decision: `rm rmdir` → `validate-bash.sh` rm guard / `rm-safe-allowlist.sh`; `curl wget` → `curl-gate.py`; `git push` → `ship-rail-push-allow.sh` | hooks run BEFORE rules; an allow rule cannot clear a hook-raised prompt, so proposing it claims a clearance that cannot happen |
| `AUTO_MODE_DROP` | `auto_mode_dropped(rule)` returns a reason | inert in the mode every session runs; proposing it reads as coverage and covers nothing |
| `ASK_DENY_COLLISION` | **bidirectional** for 1-token heads and for any `FLAG_HEAD`-shaped head: the head is a prefix of, or has as prefix, any deny/ask content in the collision set (= UNION of every discovered deny/ask, fleet AND project files). **One-directional** (refuse only when a deny/ask content is a prefix OF the candidate; otherwise pass with the carve-out named in the receipt) only for ≥2-token heads ending in a sub-verb — `git stash` under `ask Bash(git stash drop:*)` is the legitimate case | deny → ask → allow across all sources; `Bash(git:*)` / `Bash(rm:*)` are refused ON PURPOSE (§10 B1-2 — A2's one-directional proposal was rejected because it mints `Bash(rm -rf:*)`) |
| `REFUSED_PROMPT_COLLISION` | ANY leaf of ANY row classified `refused` (Stop-resolved) or `denied` (transcript-confirmed rejection) — structural rows included — has this head | the operator refused exactly this verb; auto-approving inverts a recorded human decision. `abandoned` (SessionEnd-resolved, nobody answered) is a receipt flag, never a refusal |
| `MIN_EVIDENCE` | rows < 2 OR distinct sessions < 2 OR distinct ISO weeks < 2 — **no escape clause**; `approved` is only a tiebreaker. Consolidation clusters: < `--min-cluster` (2) exact entries sharing a 2-token sub-verb head | a one-row candidate is a one-shot acceptance wearing a prefix; the "unless approved" escape would have lowered the bar to 1 row exactly for prompts the operator chose NOT to persist (§10 B2-4) |
| `PATH_BOUND` | **scope-aware**: for a FLEET target any head containing `/`, `~`, `$`, `tmp`, a 7+-hex or all-digit token; for a PROJECT-LOCAL target the same minus repo-relative script heads (`./scripts/x.sh`, `scripts/x.sh`, `./bin/x`), which may pass only into the project file the acceptances came from | a relative prefix names a location, not a program — at fleet scope it grants whatever sits at that path in any cwd (§10 B1-7) |
| `TOKEN_CAP` | head > 3 tokens or contains `*`/`?`/`[`; consolidation heads > 2 tokens | prefix form only, never a wildcard mid-rule (F1/F7); 3-token heads rescue 2 of 1,365 exact entries (A2) |

Every gate is re-run at **apply time** against the LIVE files and the LIVE archive — apply writes
`proposed ∩ fresh`, so a tampered or decayed proposal can only SHRINK the set (§3.3). Age is a WARN
line, never a gate.

### 3.3 `--check` (preview, read-only) and `--apply` (operator-run)

- `--check [PROPOSAL]` re-runs the FULL pipeline live and prints, per proposed rule, keep/drop with
  the gate code, the per-target diff apply would make, and the receipt (rows, sessions, weeks,
  projects, widening distribution). Read-only; exit 0 when ≥1 rule would apply, **exit 1 when nothing
  would** — it doubles as the backlog row's `--falsifier` (§5): exit 0 ⇔ the row still stands.
- `--apply [PROPOSAL]` (default `latest.json` under the out dir — the queue row carries NO path or
  rule text, §10 B1-5c) writes `proposed ∩ fresh`. Consent is `CONFIRM=1`, given by the operator's
  typed `yes` at the `cc-do` layer (cc-do runs `bash -c` with stdin `</dev/null`, so the tool must
  not demand a tty of its own). Without `CONFIRM=1` it behaves as `--check`.
- **In-session refusal is enforced at the chokepoint, not by an env check the agent controls:**
  `hooks/validate-bash.sh` gains a deny arm — a leaf whose argv carries a token with basename
  `cc-permission-harvest` AND the token `--apply` is denied (hooks precede rules and the classifier
  and cannot be unset by the agent). The tool's own `CLAUDECODE`/`CLAUDE_CODE_SESSION_ID`/
  `CLAUDE_CODE_ENTRYPOINT` check stays as the courtesy message. There is NO override variable.
- Targets: **fleet** = every discovered `~/.claude*/settings.json` (backup/`pre-` names excluded),
  written via `os.path.realpath`, and refused (exit 4, named) if a realpath resolves inside a git
  worktree; **project-local** = the `.claude/settings.local.json` a consolidation cluster came from
  (must be gitignored — `git check-ignore`; a tracked `.claude/settings.json` needs an explicit
  `--target`). Worktree-local settings files are evidence, never targets.
- All-or-nothing per run: backup every target (`.permharvest-bak-<UTC>`), stage `.tmp`, validate JSON
  + rule presence in every tmp, `os.replace` each; on any failure restore every touched file. Append
  to `permissions.allow` preserving order, 2-space indent, trailing newline. Idempotent: present → no-op.
- Then removes exact entries the new prefixes provably shadow in the SAME file (`dead_entries`) and
  reports both counts. Prints every rule with its evidence lines and every per-file diff before
  writing (the record the operator's `yes` was given over). Re-reads each written file to verify.
- `--only RULE…` / `--skip RULE…` edit the set without editing JSON. `tool.sha` in the proposal is
  compared with the running tool's sha — mismatch is a WARN, never silent.
- Exit 4 = a rule failed a gate at apply time or a target is refused (named); 5 = write failure
  (files restored); a rule whose evidence merely decayed is a NAMED DROP, exit 0.

### 3.4 JSON proposal (schema 1) — buckets are MECE and SUM to `inputs.rows` (asserted in bats)

```json
{"schema":1,"generated_utc":"…","tool":{"sha":"…"},"rules_snapshot":"today",
 "inputs":{"archive_dir":"…","rows":3728,"rows_in_window":2968,"sessions_in_window":0,"oracle_age_s":0,"window_days":30,
           "settings_files":[{"path":"…","scope":"fleet|project|worktree","allow":339,"deny":41,"ask":6}],
           "corpus_records":286466,"corpus_scope":"validate-bash pass-through, pre-rewrite","blind":[]},
 "mode":"auto",
 "buckets":{"structural":0,"hook_raised":0,"ask_hit":0,"deny_hit":0,"truncated":0,"hook_or_classifier":0,"rule_gap":0,"gap_unrecoverable":0},
 "resolution":{"approved":0,"refused":0,"denied":0,"abandoned":0,"collateral":0,"unknown":0},
 "structural":{"by_kind":{"command_substitution":0},"unverified_kinds":["function_def","case"],"top_verbs":[["rm",968]]},
 "hook_raised":{"by_hook":{"curl-gate":0,"validate-bash":0}},
 "proposed":[{"rule":"Bash(gh pr view:*)","target":"fleet|<path>","distinct_projects":2,"prompts_cleared":{"approved":0,"unknown":0,"total":0},
              "sessions":0,"weeks_present":2,"waited_s":0,"local_rules":{"recovered":0,"unrecoverable":0},
              "evidence":[{"ts":0,"cwd":"…","command":"…","resolution":"unknown"}],
              "widening":{"count":0,"next_tokens":[["view",12],["list",3]],"samples":[]},
              "shadows":["Bash(gh pr view 12 --json state)"],"gates":{"ACE_CLASS":"pass","ARG_EXEC":"pass","…":"pass"}}],
 "refused":[{"rule":"Bash(bash:*)","would_clear":0,"code":"ACE_CLASS","reason":"…"}],
 "consolidation":[{"file":"…","prefix":"Bash(gh pr view:*)","shadows":[],"present":false,"gates":{}}],
 "unretirable":[{"file":"…","head":"ssh -i","entries":181,"reason":"AUTO_MODE_DROP"}],
 "apply_hint":"CONFIRM=1 cc-permission-harvest --apply"}
```

---

## 4. Design — `hooks/lib/permission_matcher.py` (shared; the ONE state model)

Faithful Python port of the binary's Bash matcher as documented in
`docs/research/permission-matcher-truth-2026-08-20.md` §1–§3, §5, §6. `bin/cc-permission-audit`
imports it and drops its private `matches()/norm()`, `_classify`, `auto_mode_dropped`, `dead_entries`
copies — its three existing suites are the regression guard for the move (memory:
sibling-auditors-must-share-the-state-model).

API contract (C2 codes against this; C1 implements it):

```python
parse_rule(rule) -> Rule(tool, kind: 'bare'|'exact'|'prefix'|'wildcard', content, head) | None
ENV_ALLOWLIST: frozenset (38 names)      WRAPPERS = {timeout,time,nice,stdbuf,nohup,command,builtin,noglob}
normalize_leaf(text, *, strip_all_env=False) -> str   # comments, env prefix (allowlist; all for deny/ask), wrappers, first-token unquote, ws collapse, /dev/null redirect strip
split_leaves(cmd) -> Decomposition(kind: 'simple'|'compound'|'structural', leaves: list[str], structural: list[str], too_long: bool)
   # structural kinds: command_substitution backtick process_substitution subshell command_group background redirect_file heredoc bash_c too_long multi_cd cd_git_compound unbalanced
rule_matches_leaf(rule, leaf, behavior) -> bool        # exact ===; prefix: ws-normalised, space boundary, `xargs <prefix>`; wildcard: glob, ' .*' optional-tail rule; behavior deny/ask ⇒ strip_all_env
leaf_verdict(leaf, rules) -> ('deny'|'ask'|'allow'|'none', matched_rule|None)
command_verdict(cmd, rules) -> Verdict(outcome: 'allow'|'ask'|'deny'|'structural', uncovered: list[str], structural: list[str], matched: dict)
BUILTIN_READONLY -> is_builtin_readonly(leaf)          # informational: docs' read-only set keys on the bare name; an absolute path escapes it
auto_mode_dropped(rule) -> reason | None               # moved verbatim from cc-permission-audit
ace_reason(head_tokens) -> reason | None                # §3.2 ACE_CLASS incl. persistence/launch verbs
arg_exec_reason(head_tokens) -> reason | None           # §3.2 ARG_EXEC static table; None when the head pins past it
flag_head(head_tokens) -> bool                          # §3.2 FLAG_HEAD
shell_keyword(head_tokens) -> bool                      # §3.2 SHELL_KEYWORD
hook_owner(head_tokens) -> hook_name | None             # §3.2 HOOK_OWNED static table
dead_entries(allow) -> (survivors, dead)                # moved verbatim from cc-permission-audit
classify_row(row) -> 'approved'|'refused'|'abandoned'|'collateral'|'unknown'   # Stop ⇒ refused, SessionEnd ⇒ abandoned; PostToolUseFailure treated like PostToolUse
denial_oracle(rows, transcript_roots) -> {row_key: 'denied'}   # transcript tool_result "doesn't want to proceed" joined by tool_sig or exact command within the same session_id; roots = ~/.claude*/projects/<slug>/{<sid>.jsonl, <sid>/**/*.jsonl}
load_rulesets(paths, mode='auto') -> RuleSet(allow, deny, ask, by_file, dropped)   # union semantics; mode='auto' removes auto_mode_dropped allow rules from `allow` into `dropped`
read_archive(archdir, cutoff) -> (rows, bad, unreadable, files, heartbeat_age_s)
discover_settings(explicit=None, names=(...), roots=(~/.claude*, ~/Development)) -> [(path, scope)]  # scope ∈ fleet|project|worktree
rules_in_force_for_cwd(fleet, cwd, stop_at) -> (RuleSet, 'recovered'|'unrecoverable')
read_corpus(paths, since_ts) -> iter[(ts, sid, command)]   # anchored RECORDS, .gz aware
```

The splitter must be **quote-aware end to end**: `smart-bash-allowlist.split_segments` refuses on `<(`
even inside quotes (a Python regex such as `<(script|style)` shredded commands into garbage leaves in
A1) — mirror its structure, do not inherit that pre-check. The env allowlist is copied VERBATIM from
the matcher doc (it lists 39 names, not 38).

Fidelity suite `tests/permission-matcher.bats`: every row of the matcher doc's probe tables (§1 five
forms, §2 measured behaviour table incl. loops/conditionals decomposed, comment/wrapper/env rows,
`git status *` matching bare `git status`, double-space exact DENY, `LS -la` case, `xargs`), run
through `python3 -c` against the lib, one `@test` per row so a divergence names its row.

---

## 5. Design — recurring run (revised after wave B; the original text is in §10 B3-1/2/4)

- `scripts/permission-harvest-run.sh` (launchd wrapper, shape of `scripts/worktree-gc-infra-run.sh`):
  line-1 `export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"` (system
  first), `set -uo pipefail`, lock, seams for every path and binary (`CC_PERMHARVEST_BIN`,
  `CC_PERMHARVEST_OUT`, `CC_PERMHARVEST_EVIDENCE`, `CC_PERMHARVEST_BACKLOG`, `CC_PERMHARVEST_DAYS`),
  invokes the tool by ABSOLUTE interpreter — `/usr/bin/python3 "$HOME/.claude/bin/cc-permission-harvest" 30 --json --out ~/.claude/autonomy/permission-harvest/`
  (launchd's PATH resolves `python3` to 3.9.6; the interactive one to 3.11 — the gate runs the
  interpreter launchd will). Appends ONE JSON line to `~/.claude/logs/permission-harvest.jsonl` —
  the fleet **evidence** path AND the 8-week **trend store** the skill reads:
  `{ts, verdict: proposed|nothing|blind|error, rc, proposed, refused, rows_in_window, sessions_in_window,
  oracle_age_s, structural_share, hook_raised_share, rule_gap, top_structural_kind, consolidation_prefixes,
  consolidation_retires, proposal_path, sha}`. Prunes proposal files > 90 d.
- **Operator step — the KEY-4 brake recipe** (`needs` accepts no `--condition`; §9 Q1): iff
  `proposed + consolidation_prefixes > 0`, file
  `cc-backlog needs "Apply the N harvested allow rules in proposal-<UTC>.json (proposed <YYYY-MM-DD>)" --project claude-infrastructure --run "$HOME/.claude/bin/cc-permission-harvest --apply" --falsifier "$HOME/.claude/bin/cc-permission-harvest --check"`.
  The title varies ONLY in digits, so the brake folds a live row and updates its `run`/`needs`
  in place (one open row at any time); after the operator's `cc-do <id>` marks it `done`, the next
  week's row has a new event key. The `--run` payload carries no path and no rule text (the tool
  resolves `latest.json` itself — nothing attacker-controllable rides the queue). The autonomy
  sweep's currency pass runs the `--falsifier`: `--check` exits 0 only while something would still
  apply, so a proposal that decays closes its own row. `proposed = 0` ⇒ `verdict=nothing`, exit 0,
  no row. BLIND ⇒ exit 3 (S4 FAILING on the fleet board — no `ok_exits` column, deliberately).
- `launchd/com.claude.permission-harvest.plist`: `StartCalendarInterval` Weekday 0 · Hour 4 ·
  Minute 17; **`RunAtLoad` true** (a read-only reporter seeds its evidence at bootstrap; the lock
  makes login re-runs idempotent); `/bin/bash -c 'exec "$HOME/.claude/scripts/permission-harvest-run.sh"'`
  (launchd expands neither `~` nor `$HOME` in ProgramArguments; Standard*Path are literal
  `/Users/chrisren/.claude/logs/permission-harvest.{out,err}.log`); the wrapper execs itself through
  `/usr/sbin/taskpolicy -c utility` (never `ProcessType Background`, migration 0016's lesson).
- `launchd/fleet.manifest` row: `com.claude.permission-harvest | run | 604800 | ~/.claude/logs/permission-harvest.jsonl | 6 | 18-fleet-activate.sh`
  — `interval_s` **604800**, not 0: cc-fleet's stale bound is `interval × 3`, and `0` means DAILY
  (86400 × 3 = 72 h), which reads a healthy weekly job STALLED four days of every seven (MEASURED on
  `com.chrisren.watch-claude-code-2118-hold`). Amend the header sentence: "0 = DAILY calendar; a weekly
  calendar job declares 604800".
- **No migration, no bespoke activation script.** `install.sh:1051-1122` already copies a NEW
  manifest-`run` plist into `~/Library/LaunchAgents` and `bootstrap`s it at every converge (the
  landed manifest row IS the reviewed intent); a c10 migration would file an operator step for a
  bootstrap that has already happened and can never transition to applied. `18-fleet-activate.sh`
  (the generic bootout→enable→bootstrap used by 20 rows) is the manifest's `activate` for the
  NOT-INSTALLED / DISABLED recovery arms.
- **Two `hooks/validate-bash.sh` arms + one beacon change** (owned by unit C3): (a) the
  `cc-permission-harvest --apply` deny arm (§3.3); (b) a join-able decision log — one JSONL append
  `{ts, sid, decision, reason}` to `~/.claude/logs/validate-bash-decisions.jsonl` inside `deny()`
  and `warn()` (the rare path; mirrors `curl-gate.py`'s `AUDIT_LOG`) so step 3b can attribute
  rm-guard asks the way it attributes curl-gate asks; (c) `hooks/cc-permission-beacon.sh`
  `CC_PERMARCHIVE_MAXLEN` default 3500 → 12000 (the 4 KiB atomic-append premise it was sized for
  was measured false and replaced by the mkdir lock; 84 rows / 126 h are `truncated` today).

---

## 6. Design — `skills/permission-harvest/SKILL.md`

Triggers: `/permission-harvest`, "harvest permission prompts", "improve the allowlist", "why am I
being prompted", the weekly review. The skill: (1) runs `cc-permission-harvest 30` (read-only) and
relays the report verbatim; (2) states the ceiling honestly from the report's own buckets (structural
vs rule-gap); (3) DRIVES what an agent can — STRUCTURAL clusters become hook-category work
(`hooks/lib/smart-bash-allowlist.py`), filed only with an impossibility class; (4) hands the apply to
the operator as the ONE `cc-do` step the wrapper already filed (or files it); (5) NEVER runs `--apply`
in-session, never edits `settings*.json`, never proposes an ACE verb. Reading the JSON, the blind
states, and the refusal codes are documented so a session can answer "why was X not proposed".

---

## 7. File map

| Unit | Files |
|---|---|
| C1 | `hooks/lib/permission_matcher.py` · `tests/permission-matcher.bats` · refactor `bin/cc-permission-audit` to import (its suites must stay green) |
| C2 | `bin/cc-permission-harvest` (python3, executable, docstring-led like `cc-permission-audit`) |
| C3 | `scripts/permission-harvest-run.sh` · `launchd/com.claude.permission-harvest.plist` · `launchd/fleet.manifest` (+1 row, +1 header sentence) · `hooks/validate-bash.sh` (two arms: apply-deny + decision log) · `hooks/cc-permission-beacon.sh` (MAXLEN default) · `tests/permission-harvest-wiring.bats` · `tests/validate-bash-permharvest.bats` (positive + mutant for both arms) — *(0022 migration and 44-activate DROPPED, §10 B3-4)* |
| C4 | `skills/permission-harvest/SKILL.md` · cross-link paragraphs in `docs/research/permission-prompts-2026-08-23.md` (§6) and the matcher doc's DO #8 · `hooks/smart-bash-allowlist.sh:26-29` header correction (a hook `allow` does NOT bypass deny/ask — `Mfr` re-check) · wave-A docs already in place |
| C5 | `tests/cc-permission-harvest.bats` · `tests/cc-permission-harvest-apply.bats` · `tests/fixtures/permission-harvest/{archive/*.jsonl,settings/**,corpus.log,curl-audit.jsonl,transcripts/**}` |

Install path: `install.sh` links `bin/`, `scripts/`, `hooks/lib/*.py`, `skills/*/`, `launchd/` into
the live layer per-file; a NEW file is absent live until `scripts/deploy-live.sh` converges
(`LIVE_ADDS` rung) — the close drives that.

---

## 8. Test plan (what each suite proves)

- **Matcher fidelity** — every probe row in the truth doc; a divergence fails by row name.
- **Harvester** (fixtures): approved simple prompt → proposed; approved compound with one uncovered
  leaf → that leaf's head proposed and `prompts_cleared` exactly recomputed; structural rows land in
  STRUCTURAL and never in a candidate's count; refused-only-leaf → `REFUSED_PROMPT_COLLISION`;
  `Bash(bash:*)`/`Bash(python3:*)` (the 2026-08-23 refuted set) → `ACE_CLASS`; bare `curl` →
  `AUTO_MODE_DROP`; `git push` → `ASK_DENY_COLLISION` against a fixture ask rule; a path-ful head →
  `PATH_BOUND`; one-prompt candidate → `MIN_EVIDENCE`; per-cwd local rule suppresses a false gap;
  0-proposed run exits 0 with `proposed=0`; missing/unreadable archive exits 3 and says BLIND;
  JSON validates against schema 1; consolidation shadows exact entries.
- **Harvester, added after wave B**: buckets sum to `rows` (MECE); a curl row with a matching
  `curl-audit.jsonl` ask within ±15 s lands in `hook_raised`, never in a candidate's count; an
  `abandoned` (SessionEnd) row does NOT trigger REFUSED_PROMPT_COLLISION while a Stop row does; a
  transcript fixture carrying the rejection text marks its row `denied`; `Bash(git rebase:*)` →
  `ARG_EXEC`; `Bash(rm -f:*)` → `FLAG_HEAD`; `Bash(do:*)` → `SHELL_KEYWORD`; `Bash(rm:*)` →
  `HOOK_OWNED`; `Bash(git stash:*)` under `ask Bash(git stash drop:*)` PASSES with the carve-out named
  (one-directional for 2-token sub-verbs) while `Bash(git:*)` under `ask Bash(git push:*)` is REFUSED;
  a corpus fixture with a multi-line record yields `widening.count == 1`, not 5; auto-dropped fleet
  rule `Bash(python3:*)` does NOT count as covering `python3 x.py` in mode auto; an archive whose
  heartbeat is 4 days old with rows all outside the window exits 3 `oracle-dark`, not `proposed=0`;
  a consolidation cluster of 2 exact `gh pr view …` entries in a project-local fixture proposes
  `Bash(gh pr view:*)` INTO that file and lists both as shadows; `./scripts/x.sh` heads pass into a
  project-local target and are refused for a fleet target; `ssh -i` ×3 lands in `unretirable`.
- **Apply / check**: `--check` exits 0 with ≥1 applicable rule and 1 with none; `--apply` without
  `CONFIRM=1` writes nothing (md5 before/after); `CONFIRM=1` writes all five fixture copies atomically
  with backups and re-run is a no-op; a rule injected into `proposed[]` that the fresh run does not
  produce is DROPPED by name, not applied; a tampered ACE rule exits 4 and md5s are unchanged; a
  decayed rule (evidence aged out) is a named drop, exit 0; `CLAUDECODE=1` prints the courtesy
  refusal (the hard stop is the validate-bash arm, tested in C3's suite); a read-only target (chmod
  444 on copy 3) yields exit 5 with copies 1–2 restored byte-identical; a symlinked target is written
  through its realpath with the link preserved; a target whose realpath is inside a git worktree is
  refused (exit 4) unless named by `--target`; shadow-prune removes `Bash(gh pr view 12 --json state)`
  once `Bash(gh pr view:*)` is applied to the same file.
- **Wiring**: plist `plutil -lint`; manifest row parses with `interval_s 604800` and the header
  carries the weekly sentence; wrapper: 0-proposed → jsonl line `verdict=nothing` + exit 0 + no
  backlog call; N-proposed → exactly one `cc-backlog needs` call whose `--run` is argument-free and
  whose `--falsifier` is `--check`, and a second run with a changed N folds (stub records argv);
  harvester rc 3 → `verdict=blind`, exit 3; the wrapper invokes `/usr/bin/python3` explicitly;
  `validate-bash.sh`: a leaf `cc-permission-harvest --apply` is DENIED and its mutant (`--check`) is
  not; `deny()`/`warn()` append one parseable decision line; `cc-permission-beacon.bats` still green
  with MAXLEN 12000.

---

## 9. Wiring facts (lead-measured 2026-09-08; wave A3 extends below)

- **Agent-session marker:** an agent-session Bash carries `CLAUDECODE`, `CLAUDE_CODE_SESSION_ID`,
  `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CONFIG_DIR` (measured in this session). `--apply` guards on
  `CLAUDECODE` (and `CLAUDE_CODE_SESSION_ID` as a second witness); a `cc-do`-run operator shell has neither.
- **Python:** `python3` on the interactive PATH is 3.11.4 (`/Library/Frameworks/Python.framework/Versions/3.11/bin`);
  `/usr/bin/python3` is Apple's (3.9-class). Target **3.9-compatible syntax** in both Python deliverables
  (no `match`, no `X | Y` annotations at runtime, `from __future__ import annotations`).
- **Live-layer linking:** `install.sh:340` links `hooks/lib/*.sh` AND `hooks/lib/*.py` per-file into
  `~/.claude/hooks/lib/`; `bin/`, `scripts/`, `skills/<name>/` are linked per-file/dir too. A bin tool
  locates the lib via `os.path.dirname(os.path.realpath(__file__))` (idiom: `bin/cc-eligible:972`),
  falling back to `${CLAUDE_CONFIG_DIR:-~/.claude}/hooks/lib`.
- **`cc-backlog needs` signature:** `needs "<step>" [--run C] [--project P] [--session S]`
  (`bin/cc-backlog:127`); `--condition` is an `add`-verb key (`:13`, `:359`). A3 settles the weekly
  idempotency recipe (Q1).
- **fleet.manifest owner row:** **6** — *Guardrail/hook layer — what a session may do* (validate-bash,
  permission rails), not 12 (the fleet itself).
- **Activation template:** `docs/activation/pending-activation/43-autonomy-sweep-band-activate.sh`
  (REPO→live copy only, `bootout`+`bootstrap`, idempotent, `CC_ACTIVATE_REPO`/`CC_ACTIVATE_LA_DIR` seams).
- **Migration precedent:** `migrations/0016-autonomy-sweep-band-plist.sh` — c10, premise re-derived at
  consumption, refuses to file when the SSOT lacks the change. Next number: **0022**; next activation: **44**.
- **Archive row shape** (for fixtures): `{session_id, ts, resolved_ts, waited_s, resolved_by
  (PostToolUse|Stop|SessionEnd), cleared_tool, cleared_tool_use_id, tool_use_id ("" in 0/3,641 rows),
  tool_name, tool_input{command,…}|tool_input_summary, cwd, tool_sig, cleared_tool_sig}`; files are
  `<YYYY-MM>.<sid>.<pid>.jsonl` (3,231 files, 3,838 rows).

**Wave A3 facts (READ/MEASURED, file:line in the wf journal `wf_395460de-802`):**
- `cc-backlog needs "<step>"` accepts ONLY `--run C --falsifier P --project P --session S`; any other
  flag is `unknown arg` rc 2 (`bin/cc-backlog:3370-3400`). It mints `add --source needs` then `block`;
  `run`/`needs` ride the block record. The KEY-4 brake (`:518-560`, `:3475-3520`) folds a re-file
  whose title differs only in DIGITS onto the live row and re-`block`s it with the new `--run`/`--needs`.
  A row `done` is never re-opened by re-`add` (`:1975-1990`) and `block` over done is rc 4.
- `cc-do <12-hex-id>` reads `list --blocked --json` (status MUST be blocked), requires `.run`, asks a
  typed `yes` (`CC_DO_ASSUME_YES=1` skips; non-TTY ⇒ rc 3 NOTHING RAN), runs `bash -c "$cmd" </dev/null`,
  and on exit 0 appends `done --evidence "cc-do ran: <cmd> (exit 0)"` (`bin/cc-do:397-447`).
- `--falsifier` probes are RUN by the autonomy sweep's currency pass (`cc-premise sweep --record
  --close-falsified 25`, every 6 h): probe exit 0 ⇒ row CLOSED; non-zero ⇒ live (`scripts/autonomy-sweep.sh:1162-1176`).
- `cc-fleet` S5 STALLED reads the evidence FILE MTIME (`stat -f %m`), bound = `interval_s × 3`;
  `interval_s 0` ⇒ 86400 × 3 = 72 h; S3 NEVER-RAN = `runs = 0` AND no evidence file. 7th manifest
  column `ok_exits` optional. (`bin/cc-fleet:88,108,136,345-377`.)
- `install.sh` links per-file: `hooks/*.{sh,py}`, `hooks/lib/*.{sh,py}`, `scripts/*.sh`, `bin/cc-*`
  (a differently-named bin file is NOT linked), `skills/<name>/**`; plists are a COPY class handled by
  the LaunchAgents block (`:1026-1122`) which also `bootstrap`s a manifest-`run` label that is not
  loaded. `deploy-live.sh` `link_refresh()` repairs missing `bin/cc-*` links every 600 s tick
  without an advance (`scripts/deploy-live.sh:1384-1415`).
- Commit gate: `.git/hooks/pre-commit` enforces author email only; NO lint runs at commit — lints
  run in `/ship` (`ship-land.sh`) and `postland-verify`. Lints and their one-line rules:
  pipefail-sigpipe (no `producer | grep -q/head` under pipefail) · utc-stamp (`Z` stamps from
  `date -u`) · self-path (never derive REPO from `dirname $0`) · unattended-path (launchd/hook/bats
  targets resolve binaries only via the stock floor PATH or absolute paths) · git-identity ·
  test-hermeticity (no real `~/.claude` in tests) · bats-testname-eval (plain-string test names) ·
  permission-gate · payload · typed-send · wait-contract · bats-shellcheck.
- `bats` on PATH → `~/.claude/bin/bats` → `bin/cc-bats` (utility band, admission bound), bats 1.13.0.
- Interpreters: `/usr/bin/python3` 3.9.6 · `/opt/homebrew/bin/python3` 3.14.6 · Frameworks 3.11.4;
  all 22 `bin/` python tools use `#!/usr/bin/env python3` and py_compile clean under 3.9.
- Settings watcher (CC 2.1.220): a DIRECTORY watch (chokidar/FSEvents) on dirs that had a settings
  file at session start — an atomic `os.replace` in `~/.claude*` is the case it is built for;
  permissions-array live reload is "strongly indicated, not proven" (`permission-settings-store-2026-08-20.md` §4).
- A PreToolUse hook `allow` does NOT bypass deny/ask rules (`Mfr` re-check; docs /permissions:442);
  `hooks/smart-bash-allowlist.sh:26-29` carries the contrary claim and is corrected by unit C4.

## 10. Wave A measurements + wave B critique — what changed and why (2026-09-08)

**The measured ceiling (A1, `docs/research/permission-harvest-profile-2026-09-08.md`).** 3,728 Bash
prompts: STRUCTURAL 45.4 % · "rule gap" 46.0 % — of which 1,367/1,368 curl-only rows were curl-gate
`ask`s (hook-raised, ±15 s join), so the defensible rule gap is ~9 % · ASK_HIT 6 % · TRUNCATED 2.3 %.
Gate-passing greedy set cover clears **13–21 prompts ever (0.35–0.56 %) and 0 in the last 7 days.**
Resolution: approved 62 · refused 23 (7 Stop, 16 SessionEnd) · collateral 379 · unknown 3,264
(signatures exist only from 2026-09-08). Σ waited 1,622 h, 65.7 % of it structural.
**The acceptance corpus (A2, `…-acceptances-2026-09-08.md`).** 144 settings files; the five fleet
files hold 1,272 Bash allows, ALL `:*` prefixes, 0 exact, 0 dead, forked by exactly ONE entry
(`Bash(kitten @ send-text:*)`); 975 exact acceptances live in project `settings.local.json` (67 %
path-bound); consolidation ceiling at min-cluster 2 = 58 prefixes retiring 254; ~60 % can never be
retired (`ssh -i` ×181 auto-dropped, `perl -ne` ×82 ACE, `git -C <path>` ×82 un-normalisable);
3-token heads rescue 2 of 1,365. **Consequence:** the weekly product is, in order, the
consolidation (project-local), the attribution trend (structural/hook/rule-gap), and 0–5 archive
rules. `proposed=0` is the expected steady state and must be first-class, not a failure.

**Findings folded (lens · id · decision · conviction):**

- B1-1 **ARG_EXEC** — `git rebase -x 'touch MARK'` measured executing; new gate + static table;
  `launchctl defaults crontab at osascript automator open security export set` into ACE; worked
  example is now `Bash(gh pr view:*)`. Adopted, 95 %.
- B1-2 **collision direction + FLAG_HEAD + SHELL_KEYWORD** — A2's one-directional collision
  (conviction 85 %) REJECTED: it mints `Bash(rm -rf:*)` (11 exact acceptances) and `Bash(git:*)`
  (99). Bidirectional for 1-token and flag heads; one-directional only for ≥2-token sub-verb heads.
  Consolidation clusters keyed on 2-token sub-verbs; never mint prefixes for
  `rm mv cp chmod chown chflags ln dd truncate install` from path-bound literals. Adopted, 95 %.
- B1-3 **DANGER_WIDENING deleted** — `bash-commands.log` is written at `validate-bash.sh:1341`,
  reached only after every `deny()`/`warn()` has exited, so the corpus contains nothing the predicate
  looks for (positive control: `sudo rm` 0 hits over 194,535 records). Widening is a receipt (count +
  next-token distribution); adversarial completion moves into ARG_EXEC. Adopted, 95 %.
- B1-4 **in-session guard at the chokepoint** — an env check the agent controls is not a guard;
  `validate-bash.sh` deny arm on `cc-permission-harvest` + `--apply`; `CC_PERMHARVEST_ALLOW_IN_SESSION`
  deleted. Adopted, 95 %.
- B1-5 / B3-5 **apply = proposed ∩ fresh** — the 14-day age gate re-derived nothing about the
  evidence; full pipeline re-run at apply, decayed rules are named drops (exit 0), tampered rules can
  only shrink the set; `--run` payload argument-free; `tool.sha` mismatch WARN. Consent stays
  `CONFIRM=1` from cc-do's typed `yes` (B1-5b's own-tty demand conflicts with cc-do's `</dev/null` —
  resolved in favour of the existing consent layer, with the diff printed for the record). Adopted, 90 %.
- B1-6 / B2-5 **refused ≠ abandoned; transcript denials** — 16 of 23 "refused" rows are SessionEnd
  (nobody answered); ~19 genuine denials hide in `collateral`. `classify_row` splits Stop/SessionEnd;
  `denial_oracle` joins transcripts (`~/.claude*/projects/<slug>/{<sid>.jsonl,<sid>/**}`) by
  `tool_sig` or exact command; REFUSED_PROMPT_COLLISION fires on any leaf of any refused/denied row
  incl. structural. Adopted, 85 %.
- B1-7 **PATH_BOUND by target scope** — A2's relative-script relaxation (80 %) accepted ONLY for
  project-local targets; a relative head at fleet scope grants a location. Adopted, 90 %.
- B1-8 **realpath writes; refuse targets inside a git worktree** unless `--target`. Adopted, 90 %.
- B2-1 **HOOK_RAISED bucket + HOOK_OWNED gate + validate-bash decision log** — 80 % of the "gap" was
  hook asks; without the attribution every count re-inflates. Adopted, 95 %.
- B2-2 **corpus by anchored RECORD, `.gz` included** — 82 % of lines are continuation fragments
  (1,636,089 lines vs 286,466 records). Adopted, 95 %.
- B2-3 **mode-aware rules-in-force** — 7 fleet allows are auto-inert; 17.3 % of gap rows were
  over-credited through them. `load_rulesets(mode='auto')`. Adopted, 90 %.
- B2-4 **MIN_EVIDENCE without the approved escape; `distinct_projects`; fleet target needs ≥2
  projects.** Adopted, 90 %.
- B2-6 **MECE buckets** (+ `ask_hit deny_hit truncated abandoned hook_raised gap_unrecoverable`),
  `unverified_kinds` separated, `bash_c` moved from structural to ACE, beacon MAXLEN 3500 → 12000.
  The two missing probes (heredoc under `Bash(cat:*)`, `bash -c`) are NOT run in this wave — the
  report labels them unverified. Adopted, 85 %.
- B2-7 **rank by sessions then rows; `weeks_present ≥ 2`; Σ waited reported never ranked** — the
  top 20 rows hold 21.9 % of all waited time. Adopted, 90 %.
- B2-8 **`local_rules: recovered|unrecoverable`** (40.9 % of rows; union of project-local rules for
  the unrecoverable, excluded from MIN_EVIDENCE); the origin/main committed-settings lookup is NOT
  built (bounded). Adopted, 85 %.
- B3-1 **needs-row recipe** — `needs` takes no `--condition`; KEY-4 brake folds titles differing only
  in digits; `--falsifier "--check"` self-closes decayed rows via the sweep's currency pass. Adopted, 90 %.
- B3-2 **manifest `interval_s 604800`, `RunAtLoad true`**, header sentence. Adopted, 95 %.
- B3-3 **oracle-dark BLIND arm** — a dead beacon otherwise reads `proposed=0` forever. Adopted, 95 %.
- B3-4 **drop migration 0022 + activation 44** — `install.sh:1051-1122` bootstraps a manifest-`run`
  plist at converge; a c10 for it is born dead. `activate = 18-fleet-activate.sh`. Adopted, 85 %
  (D1 verifies the install.sh claim by reading the block before the wiring test is trusted).
- B3-6 **trend fields on the jsonl; structural-lever work filed ONCE** (condition-keyed
  `permission-harvest-structural-levers`, dod-ref the profile doc) by the lead in wave E. Adopted, 90 %.
- B3-7 **`/usr/bin/python3` explicit in the wrapper; both interpreters in the gate; close verifies
  the live layer by content.** Adopted, 95 %.

**Kept against reviewer temptation (all three critics named these):** counts from the archive,
widening from the corpus · STRUCTURAL partitioned first · `proposed=0` exits 0 with its denominator,
BLIND exits 3 with no `ok_exits` · apply is operator-run via `cc-do`, never a launchd side effect,
and writes all five forks · signature-proven resolution with `unknown` as the honest default ·
bidirectional collision at 1-token and flag heads.

**Original 8-gate table (superseded):** ACE_CLASS · AUTO_MODE_DROP · ASK_DENY_COLLISION
(bidirectional, all heads) · REFUSED_PROMPT_COLLISION ("only uncovered leaf" criterion) ·
DANGER_WIDENING (corpus regex — deleted, B1-3) · MIN_EVIDENCE (with the approved escape — deleted,
B2-4) · PATH_BOUND (shape-only) · TOKEN_CAP; plus a 14-day apply age gate (replaced, B1-5/B3-5) and an
env-only in-session guard with an override variable (replaced, B1-4).

## 11. Decisions & rationale log

- **Apply is operator-run, never a launchd side effect.** A weekly job that silently widens
  permissions is "scripting your own authorization" at machine scale; the job PROPOSES and files
  one `cc-do`-able step. Conviction 95%.
- **Counts from the archive, widening from the corpus.** The two populations answer different
  questions; conflating them is how every inflated estimate on 2026-08-23 was produced.
- **Structural first.** Only `no-rule-match` is rule-fixable; the report names the structural
  share so the operator sees the true ceiling instead of a number that cannot be delivered.
- **Shared matcher lib.** Two tools with two matchers would disagree on the same population;
  `cc-permission-audit`'s existing suites guard the move.
- **Prefix form only, ≤3 tokens.** The only form that is whitespace-tolerant, survives the
  auto-mode drop, and composes across compounds (matcher doc DO #1–#3).
