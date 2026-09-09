# Permission-harvest acceptance census — 2026-09-08 (wave A2)

**What this measures.** The corpus of allow/deny/ask rules the operator's "yes, don't ask again" answers
have written into every settings file on this box, so that `bin/cc-permission-harvest` step 8
(CONSOLIDATE — `docs/plans/PERMISSION_HARVEST.md` §3.1) is designed against the real shapes rather than
the 2026-08-12 figure ("2,036 distinct patterns; 48% exact; 359 embedding an absolute path") the plan §2
currently cites.

> **VERDICT (measured).** The five fleet `~/.claude*/settings.json` hold **zero exact Bash entries** —
> all 1,272 Bash allows there are already `:*` prefixes, `--prune` finds 0 dead of 1,692, and the five
> allow lists differ by exactly ONE entry. **Every exact acceptance lives in project-local files**: 975
> exact Bash entries across 52 `~/Development/*/.claude/settings*.json` (plus 390 in worktree copies, of
> which 326 are byte-copies of committed files and 64 are genuine acceptances that die with the worktree).
> Of the 975, **378 (39%) sit under a 1-token head that passes every §3.2 gate**, **639 (66% of all 1,365)
> fail at 1-, 2- AND 3-token heads**, and 3-token heads rescue **2 entries** in the whole corpus. The
> consolidation ceiling at the plan's own gates is **~254 exact entries collapsed into ~58 prefixes**
> (min-cluster 2, project files) — a ceiling set by two single-file clusters (`ssh -i` ×181 in
> `cloud-agent`, `perl -ne` ×81 in `shadcn-pivot-data-table-example`) that no gate-passing prefix can
> cover, and by the `git -C <path>` shape (82 entries) the matcher cannot normalise.

## 0. Method

* **Script (MEASURED, run 2026-09-08):** `/private/tmp/claude-501/-Users-chrisren-Development-claude-infrastructure/52e35019-17e8-40f6-a54f-3a04de70d2e6/scratchpad/a2/census.py` → `census.json` + `tables.md`;
  follow-ups `followup.py` / `followup2.py` → `followup.json`, `followup2.json`, `tables_project.md`.
  Raw `--prune` transcripts: `prune-fleet.txt`, `prune-discovered.txt`.
* **Imported, not re-implemented:** `dead_entries` (THE DEAD-ENTRY PREDICATE) and `auto_mode_dropped`
  from `bin/cc-permission-audit` via `importlib.util.spec_from_file_location` (module-level `sys.argv`
  read is neutralised by swapping `argv` during `exec_module`).
* **Rule typing** follows `permission-matcher-truth-2026-08-20.md` §1 (READ): `:*` suffix ⇒ prefix;
  unescaped `*` elsewhere ⇒ wildcard; else exact; no parens ⇒ bare.
* **Normalisation of an exact literal** follows §1 `iae` (READ): strip a leading env assignment ONLY if
  the name is in the 38-name allowlist (a foreign `VAR=` is kept — the rule can then only ever match with
  that literal prefix, F6); strip wrappers `timeout <dur>`, `time`, `nice`, `stdbuf`, `nohup`, `command`,
  `builtin`, `noglob`; unquote the first token; collapse whitespace. Heads are the first 1/2/3
  whitespace tokens of the normalised literal.
* **Gates** transcribed from the plan §3.2: PATH_BOUND (token contains `/`, `~`, `$`, `tmp`, ≥7 hex, or
  all digits), AUTO_MODE_DROP (imported), ACE_CLASS (plan list; matched on the head's first token and its
  basename; `python*` by regex), TOKEN_CAP (glob char in head), ASK_DENY_COLLISION (head is a prefix of,
  or has as a prefix, any fleet deny/ask Bash content — the plan's wording, applied literally).
* **Consolidation yield** = `dead_entries(allow + candidates)` minus `dead_entries(allow)`, per file, with
  candidates `Bash(<raw head>:*)` (raw = un-normalised first tokens, because the predicate is literal).
  The predicate does NOT count a one-token literal as shadowed by its own `:*` (documented "not asserted");
  198 exact literals are one-token.
* **Discovery:** `~/.claude*/settings.json` + `settings.local.json` excluding `*.bak*`, `*pre-*`,
  `*backup*` (5 found — no `~/.claude*/settings.local.json` exists); every `.claude/settings.json` and
  `.claude/settings.local.json` under `~/Development` to depth 5 skipping `node_modules`/`.git` — 52
  project files + 87 under `.worktrees/` (reported separately as copies). 0 unreadable.
* **MEASURED vs READ vs INFERRED** is marked per claim below. Nothing here reads the permission archive;
  this census is the RULES side only.

## 1. Corpus shape (T1)

### T1 — per-file census (allow / deny / ask · Bash allow by rule type)

**Fleet (5 × `~/.claude*/settings.json`; no `~/.claude*/settings.local.json` exists):**

| file | allow | deny | ask | Bash | non-Bash | exact | prefix | wildcard | bare | exact w/ path | exact env-foreign | exact wrapper |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `~/.claude/settings.json` | 339 | 41 | 6 | 255 | 84 | 0 | 255 | 0 | 0 | 0 | 0 | 0 |
| `~/.claude-next/settings.json` | 339 | 41 | 6 | 255 | 84 | 0 | 255 | 0 | 0 | 0 | 0 | 0 |
| `~/.claude-quaternary/settings.json` | 338 | 41 | 6 | 254 | 84 | 0 | 254 | 0 | 0 | 0 | 0 | 0 |
| `~/.claude-secondary/settings.json` | 338 | 41 | 6 | 254 | 84 | 0 | 254 | 0 | 0 | 0 | 0 | 0 |
| `~/.claude-tertiary/settings.json` | 338 | 41 | 6 | 254 | 84 | 0 | 254 | 0 | 0 | 0 | 0 | 0 |

**Project-local (`~/Development/*/.claude/settings*.json`, depth ≤5, non-worktree), sorted by allow count:** — top 12 of 52 by allow count (full table: `tables.md` in the census dir):**

| file | allow | deny | ask | Bash | non-Bash | exact | prefix | wildcard | bare | exact w/ path | exact env-foreign | exact wrapper |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `reso-management-app/.claude/settings.local.json` | 497 | 0 | 0 | 463 | 34 | 285 | 155 | 23 | 0 | 223 | 15 | 0 |
| `shadcn-pivot-data-table-example/.claude/settings.local.json` | 300 | 0 | 0 | 204 | 96 | 154 | 44 | 6 | 0 | 135 | 14 | 0 |
| `cloud-agent/.claude/settings.local.json` | 269 | 2 | 0 | 249 | 20 | 207 | 34 | 8 | 0 | 201 | 0 | 1 |
| `finance-ai-web-app/.claude/settings.local.json` | 132 | 3 | 15 | 110 | 22 | 15 | 95 | 0 | 0 | 10 | 3 | 1 |
| `natural-text-to-voice-extension/.claude/settings.local.json` | 125 | 0 | 0 | 113 | 12 | 41 | 72 | 0 | 0 | 37 | 0 | 0 |
| `voiceink/.claude/settings.local.json` | 121 | 0 | 0 | 109 | 12 | 43 | 61 | 5 | 0 | 38 | 1 | 0 |
| `linkedin-resume-discovery/.claude/settings.local.json` | 118 | 0 | 0 | 1 | 117 | 0 | 1 | 0 | 0 | 0 | 0 | 0 |
| `claude-infrastructure/.claude/settings.local.json` | 95 | 0 | 0 | 84 | 11 | 52 | 24 | 8 | 0 | 37 | 2 | 2 |
| `reso-qa-runner/.claude/settings.json` | 82 | 19 | 2 | 80 | 2 | 8 | 58 | 14 | 0 | 2 | 0 | 0 |
| `reso-management-app/.claude/settings.json` | 78 | 19 | 2 | 76 | 2 | 6 | 56 | 14 | 0 | 0 | 0 | 0 |
| `domain-discovery/.claude/settings.local.json` | 73 | 0 | 0 | 15 | 58 | 11 | 4 | 0 | 0 | 3 | 0 | 0 |
| `convert-pdf-to-md/.claude/settings.local.json` | 68 | 0 | 0 | 38 | 30 | 9 | 28 | 1 | 0 | 5 | 0 | 0 |

**Aggregates:**

| group | files | allow | deny | ask | Bash | non-Bash | exact | prefix | wildcard | bare | exact w/ path | exact env-foreign | exact wrapper |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| fleet | 5 | 1692 | 205 | 30 | 1272 | 420 | 0 | 1272 | 0 | 0 | 0 | 0 | 0 |
| project | 52 | 2513 | 45 | 19 | 1870 | 643 | 975 | 766 | 129 | 0 | 787 | 35 | 4 |
| worktree | 87 | 3871 | 684 | 72 | 3785 | 86 | 390 | 2881 | 514 | 0 | 131 | 8 | 2 |
| all | 144 | 8076 | 934 | 121 | 6927 | 1149 | 1365 | 4919 | 643 | 0 | 918 | 43 | 6 |


Notes (MEASURED): fleet non-Bash allows are 74 `WebFetch(domain:…)` + 2 `Skill(…)` + 8 bare tool names
per file. Project non-Bash: 547 `WebFetch`, 66 `Read`, the rest single digits. Wildcard Bash entries:
100 distinct strings, 98 of them in project files — shapes: 79 `x *` (space-star; matches bare `x` too
per §1), 20 `x*` (glued), 30 mid/multi-glob (e.g. a whole quoted `ssh … "tmux … | grep … | head -1"`
line saved with a `*` inside it). Exact literals: 956 distinct of 1,365; token-length histogram
1:198 · 2:198 · 3:333 · 4:86 · 5:80 · 6:85 · 7:34 · ≥8:351; 918 (67%) contain a PATH_BOUND token
(slash 880, tilde 259, `$` 162, tmp 107, digits 101, hex 7); 207 look one-shot (tmp/hex/digit token);
43 carry a foreign env prefix (15 reso, 14 shadcn-pivot); 46 are multi-line; 14 contain a heredoc;
154 contain `&&`/`;` and 98 a pipe — i.e. the F19 splitter did NOT split them (they were saved whole).

## 2. The fleet fork and the collision set (T2)

### T2 — fleet fork (allow-list set difference across the five `settings.json`)

union 339 · intersection 338 · forked entries 1 · in-file duplicates: ~/.claude/settings.json=0, ~/.claude-next/settings.json=0, ~/.claude-quaternary/settings.json=0, ~/.claude-secondary/settings.json=0, ~/.claude-tertiary/settings.json=0

| forked allow entry | present in |
|---|---|
| `Bash(kitten @ send-text:*)` | .claude, .claude-next |

deny lists identical across 5: **True** · ask lists identical across 5: **True**

**Fleet DENY union (41):** `Bash(chflags -R noschg:*)` · `Bash(chflags -R nouchg:*)` · `Bash(chflags noschg:*)` · `Bash(chflags nouchg:*)` · `Bash(chmod -R 777:*)` · `Bash(chmod 777:*)` · `Bash(dd:*)` · `Bash(eval:*)` · `Bash(exec:*)` · `Bash(fdisk:*)` · `Bash(git clean:*)` · `Bash(git push --force:*)` · `Bash(git push -f:*)` · `Bash(mkfs:*)` · `Bash(parted:*)` · `Bash(rm -fr /)` · `Bash(rm -rf $HOME)` · `Bash(rm -rf $HOME/)` · `Bash(rm -rf .git)` · `Bash(rm -rf .git/)` · `Bash(rm -rf /)` · `Bash(rm -rf /*)` · `Bash(rm -rf ~)` · `Bash(rm -rf ~/)` · `Bash(shred:*)` · `Bash(su:*)` · `Bash(sudo:*)` · `Bash(truncate:*)` · `Bash(unlink:*)` · `Bash(wget:*)` · `Read(./**/*.key)` · `Read(./**/*.pem)` · `Read(./**/*credentials*)` · `Read(./**/*secret*)` · `Read(./.env)` · `Read(./.env.local)` · `Read(./.env.local.*)` · `Read(./.env.production)` · `Read(./.env.staging)` · `Read(./credentials.json)` · `Read(./secrets/**)`

**Fleet ASK union (6):** `Bash(fly deploy:*)` · `Bash(git push:*)` · `Bash(git reset --hard:*)` · `Bash(git restore:*)` · `Bash(git stash clear:*)` · `Bash(git stash drop:*)`

**Deny/ask found ONLY in project/worktree files (union semantics ⇒ collision set widens per cwd):** deny 23: `Bash(*>*/.claude/agents/*)` · `Bash(*>*/.claude/hooks/*)` · `Bash(*>*/.claude/settings*.json)` · `Bash(*>*/.claude/skills/*/SKILL.md)` · `Bash(*>*/.env*)` · `Bash(*>*/.github/workflows/*)` · `Bash(*>*/drizzle/*)` · `Bash(*>*/middleware.*)` · `Bash(*>*/src/app/actions/*)` · `Bash(*>*/src/app/api/*)` · `Bash(gh pr create)` · `Bash(gh pr create:*)` · `Bash(npx --package*)` · `Bash(npx -p *)` · `Bash(npx -y -p *)` · `Bash(rm -rf /:*)` · `Bash(rm -rf ~:*)` · `Bash(sed -i*/.claude/*)` · `Bash(sed -i*/.env*)` · `Bash(wget *)` · `Read(./.env.*)` · `Read(./apps/backend/app/config/secrets.*)` · `WebFetch` — ask 16: `Bash(bun run deploy:*)` · `Bash(docker system prune:*)` · `Bash(git push --force:*)` · `Bash(git push -f:*)` · `Bash(mv:*)` · `Bash(npm run deploy:*)` · `Bash(pnpm add !(-D *))` · `Bash(pnpm remove*)` · `Bash(rm -r:*)` · `Bash(rm -rf:*)` · `Edit(.env)` · `Edit(.env.*)` · `Read(.env)` · `Read(.env.*)` · `Write(.env)` · `Write(.env.*)`


MEASURED: the five files have five different md5s (sizes 38,096–41,763 B) but their `permissions.allow`
lists differ by ONE entry (`Bash(kitten @ send-text:*)`, present only in `.claude` and `.claude-next`);
deny (41) and ask (6) are byte-identical across all five. The md5 spread is therefore outside
`permissions` — hooks/env/autoMode blocks — not an allow fork. The harvester's apply target is
effectively one list ×5; the "writes all five or it silently applies to one account" rule in plan §2 stays
necessary, but the reconcile step it implies is a one-entry diff, not a merge.

## 3. Heads (T3)

### T3 — heads over exact Bash allow entries

All-files version (worktree copies included; `files` column inflated by the 37 reso worktrees carrying copies of reso's committed `.claude/settings.json`) is in `tables.md`; the table that matters for design is PROJECT-only:

**1-token heads, PROJECT files only (worktree copies excluded) — 201 distinct; singletons 110; heads with ≥3 entries 58 covering 799 entries; gate-passing heads 95 covering 378 entries**

| head | entries | files | path-bound entries | head PATH_BOUND | prefix `Bash(head:*)` exists | auto-drop | ACE | shell keyword | ask/deny collision |
|---|---|---|---|---|---|---|---|---|---|
| `ssh` | 181 | 1 | 181 |  | same-file | DROP |  |  |  |
| `git` | 99 | 14 | 86 |  | same-file |  |  |  | Bash(git clean:*),Bash(git push --force:*),Bash(gi |
| `perl` | 82 | 2 | 81 |  | nowhere | DROP | perl |  |  |
| `bash` | 52 | 7 | 51 |  | same-file | DROP | bash |  |  |
| `cp` | 35 | 6 | 35 |  | same-file |  |  |  |  |
| `xargs` | 17 | 6 | 4 |  | same-file | DROP | xargs |  |  |
| `do` | 16 | 7 | 11 |  | nowhere |  |  | KEYWORD |  |
| `node` | 16 | 5 | 13 |  | same-file | DROP | node |  |  |
| `rm` | 16 | 4 | 6 |  | other-file |  |  |  | Bash(rm -fr /),Bash(rm -rf $HOME),Bash(rm -rf $HOM |
| `sed` | 15 | 5 | 15 |  | nowhere |  |  |  |  |
| `python3` | 14 | 8 | 8 |  | FLEET | DROP | python3 |  |  |
| `#` | 12 | 3 | 10 |  | nowhere |  |  | KEYWORD |  |
| `[` | 11 | 4 | 11 |  | nowhere |  |  | KEYWORD |  |
| `mkdir` | 11 | 3 | 11 |  | other-file |  |  |  |  |
| `sort` | 11 | 3 | 2 |  | other-file |  |  |  |  |
| `"/Applications/Google` | 10 | 1 | 10 | YES | nowhere |  |  |  |  |
| `for` | 10 | 4 | 1 |  | same-file |  |  | KEYWORD |  |
| `done` | 8 | 8 | 0 |  | nowhere |  |  | KEYWORD |  |
| `plutil` | 8 | 2 | 8 |  | other-file |  |  |  |  |
| `sips` | 8 | 2 | 6 |  | same-file |  |  |  |  |
| `dig` | 7 | 2 | 0 |  | other-file |  |  |  |  |
| `ls` | 7 | 1 | 7 |  | FLEET |  |  |  |  |
| `gzip` | 6 | 1 | 5 |  | other-file |  |  |  |  |
| `printf` | 6 | 4 | 1 |  | other-file |  |  |  |  |
| `scp` | 6 | 1 | 6 |  | same-file |  |  |  |  |
| `set` | 6 | 2 | 0 |  | nowhere |  |  | KEYWORD |  |
| `$LSREGISTER` | 5 | 1 | 5 | YES | nowhere |  |  |  |  |
| `$VENV_DIR/bin/python3` | 5 | 1 | 5 | YES | nowhere |  | python3 |  |  |
| `./bin/claude-accounts` | 5 | 1 | 5 | YES | other-file |  |  |  |  |
| `/usr/libexec/PlistBuddy` | 5 | 1 | 5 | YES | nowhere |  |  |  |  |
| `CLAUDE_SKIP_UPDATE=1` | 5 | 1 | 5 |  | nowhere |  |  |  |  |
| `awk` | 5 | 3 | 5 |  | other-file |  | awk |  |  |
| `claude` | 5 | 3 | 0 |  | same-file |  |  |  |  |
| `cursor` | 5 | 2 | 3 |  | same-file |  |  |  |  |
| `export` | 5 | 4 | 3 |  | nowhere |  |  | KEYWORD |  |
| `open` | 5 | 3 | 3 |  | other-file |  |  |  |  |
| `source` | 5 | 3 | 4 |  | other-file |  | source |  |  |
| `sysctl` | 5 | 1 | 0 |  | nowhere |  |  |  |  |
| `./install.sh` | 4 | 1 | 4 | YES | nowhere |  |  |  |  |
| `./scripts/rum-users.sh` | 4 | 1 | 4 | YES | nowhere |  |  |  |  |

**2-token heads, PROJECT files only (worktree copies excluded) — 337 distinct; singletons 258; heads with ≥3 entries 43 covering 575 entries; gate-passing heads 132 covering 310 entries**

| head | entries | files | path-bound entries | head PATH_BOUND | prefix `Bash(head:*)` exists | auto-drop | ACE | shell keyword | ask/deny collision |
|---|---|---|---|---|---|---|---|---|---|
| `ssh -i` | 181 | 1 | 181 |  | nowhere | DROP |  |  |  |
| `git -C` | 82 | 6 | 82 |  | same-file |  |  |  |  |
| `perl -ne` | 81 | 2 | 81 |  | nowhere | DROP | perl |  |  |
| `bash -n` | 31 | 3 | 31 |  | other-file | DROP | bash |  |  |
| `sed -n` | 14 | 4 | 14 |  | other-file |  |  |  |  |
| `mkdir -p` | 11 | 3 | 11 |  | other-file |  |  |  |  |
| `rm -rf` | 11 | 3 | 4 |  | nowhere |  |  |  | Bash(rm -rf $HOME),Bash(rm -rf $HOME/),Bash(rm -rf |
| `xargs -I` | 11 | 5 | 4 |  | nowhere | DROP | xargs |  |  |
| `"/Applications/Google Chrome.app/Contents/MacOS/Google` | 10 | 1 | 10 | YES | nowhere |  |  |  |  |
| `[ -d` | 8 | 4 | 8 |  | nowhere |  |  | KEYWORD |  |
| `for domain` | 7 | 1 | 0 |  | nowhere |  |  | KEYWORD |  |
| `# Run` | 6 | 1 | 6 |  | nowhere |  |  | KEYWORD |  |
| `dig +short` | 6 | 1 | 0 |  | nowhere |  |  |  |  |
| `do echo` | 6 | 4 | 6 |  | other-file |  |  | KEYWORD |  |
| `scp -i` | 6 | 1 | 6 |  | nowhere |  |  |  |  |
| `$VENV_DIR/bin/python3 -c` | 5 | 1 | 5 | YES | nowhere |  | python3 |  |  |
| `/usr/libexec/PlistBuddy -c` | 5 | 1 | 5 | YES | nowhere |  |  |  |  |
| `CLAUDE_SKIP_UPDATE=1 DISABLE_AUTOUPDATER=1` | 5 | 1 | 5 |  | nowhere |  |  |  |  |
| `gzip -c` | 5 | 1 | 5 |  | nowhere |  |  |  |  |
| `plutil -p` | 5 | 2 | 5 |  | nowhere |  |  |  |  |
| `python3 -c` | 5 | 3 | 4 |  | nowhere | DROP | python3 |  |  |
| `sips -g` | 5 | 2 | 5 |  | nowhere |  |  |  |  |
| `xargs -I{}` | 5 | 2 | 0 |  | nowhere | DROP | xargs |  |  |
| `./scripts/rum-users.sh --start` | 4 | 1 | 4 | YES | nowhere |  |  |  |  |
| `grep -c` | 4 | 1 | 4 |  | nowhere |  |  |  |  |
| `osascript -e` | 4 | 3 | 2 |  | nowhere |  |  |  |  |
| `python3 -` | 4 | 4 | 0 |  | nowhere | DROP | python3 |  |  |
| `$LSREGISTER -u` | 3 | 1 | 3 | YES | nowhere |  |  |  |  |
| `VALIDATE_URL="http://localhost:3002/preview/luxury-menu" nod` | 3 | 1 | 3 | YES | nowhere |  |  |  |  |
| `[ -f` | 3 | 2 | 3 |  | nowhere |  |  | KEYWORD |  |
| `do basename` | 3 | 1 | 3 |  | nowhere |  |  | KEYWORD |  |
| `git branch` | 3 | 3 | 0 |  | FLEET |  |  |  |  |
| `git stash` | 3 | 3 | 1 |  | same-file |  |  |  | Bash(git stash clear:*),Bash(git stash drop:*) |
| `ls -la` | 3 | 1 | 3 |  | nowhere |  |  |  |  |
| `mdutil -s` | 3 | 1 | 3 |  | nowhere |  |  |  |  |
| `node -e` | 3 | 2 | 3 |  | FLEET | DROP | node |  |  |
| `open -a` | 3 | 1 | 2 |  | nowhere |  |  |  |  |
| `python3 -m` | 3 | 3 | 2 |  | nowhere | DROP | python3 |  |  |
| `rm -f` | 3 | 2 | 1 |  | nowhere |  |  |  |  |
| `screencapture -x` | 3 | 2 | 3 |  | nowhere |  |  |  |  |


MEASURED, project files only: the two dominant clusters are single-file — `ssh -i` ×181 all in
`cloud-agent/.claude/settings.local.json` (each a distinct `ssh -i ~/.ssh/… user@host "…"` line) and
`perl -ne` ×73 in `shadcn-pivot-data-table-example` (+8 in reso). `git -C <path> <verb>` is 82 entries
in 6 files (voiceink 22, reso 19, natural-text-to-voice 18, claude-infrastructure 13, …); verbs after the
path: log 22, status 13, diff 8, add 7, commit 7, config 4, then singletons. 56 of those 82 have a
`Bash(git <verb>:*)` already in the FLEET — which does not cover them, because `iae` does not skip
`-C <path>` (matcher-truth §1; plan §3.1 step 5 already states this). `bash -n <path>` is 31 entries
(27 in reso) — an interpreter head, refused by ACE and dropped by auto mode, so uncoverable by rule.

Cross-checks (MEASURED): 8 heads that pass every plan gate are shell KEYWORDS or fragments — `do` 16,
`#` 12, `[` 11, `for` 10, `done` 8, `set` 8, `export` 5, `while` 3 = **73 entries (71 in project files)**.
These are the F19 splitter saving the leaves of a `for … do …; done` loop or an `if [ -d … ]` test as
separate exact rules; `Bash(do:*)` / `Bash(done:*)` are meaningless rules that the current gate list
would PASS. Among gate-passing 1-token heads in project files (95 heads, 378 entries), `git` alone is 99
(86 of them path-bound `git -C` forms) and the plan's ASK_DENY_COLLISION wording refuses `git` (it is a
prefix of `git push:*` / `git clean:*`), `rm` (prefix of the nine `rm -rf …` denies) and `chflags`; at 2
tokens it refuses `rm -rf`, `git push`, `git stash`, `rm -fr`.

## 4. Consolidation yield (T4)

### T4 — consolidation yield (`dead_entries` imported; prefixes added to their OWN file)

| head | min cluster | gates | prefixes added | distinct heads | exact entries newly dead |
|---|---|---|---|---|---|
| h1 | 1 | ungated | 432 | 194 | 721 |
| h1 | 1 | gated | 237 | 98 | 430 |
| h1 | 2 | ungated | 105 | 73 | 514 |
| h1 | 2 | gated | 59 | 40 | 277 |
| h1 | 3 | ungated | 64 | 44 | 441 |
| h1 | 3 | gated | 37 | 26 | 235 |
| h2 | 1 | ungated | 565 | 342 | 576 |
| h2 | 1 | gated | 330 | 153 | 332 |
| h2 | 2 | ungated | 82 | 61 | 375 |
| h2 | 2 | gated | 48 | 35 | 206 |
| h2 | 3 | ungated | 42 | 32 | 316 |
| h2 | 3 | gated | 26 | 19 | 166 |

exact entries total 1365 · distinct literals 956 · one-token literals (`literal == base`, NOT proven dead by the predicate) 198 · raw-head ≠ normalised-head (env/wrapper prefix; a normalised-head prefix cannot shadow them) 18


Project files only (MEASURED; worktree copies excluded):

| head | min cluster | gates | prefixes | distinct heads | newly dead |
|---|---|---|---|---|---|
| h1 | 1 | ungated | 290 | 191 | 606 |
| h1 | 1 | gated | 164 | 98 | 337 |
| h1 | 2 | ungated | 95 | 71 | 477 |
| h1 | 2 | gated | 58 | 41 | 254 |
| h1 | 3 | gated | 36 | 27 | 214 |
| h2 | 1 | gated | 187 | 154 | 270 |
| h2 | 2 | gated | 49 | 37 | 190 |
| h2 | 3 | gated | 26 | 20 | 153 |
| **combo** (h1 where it passes, else h2, else h3) | 2 | gated | **58** | — | **254** |
| combo | 3 | gated | 36 | — | 214 |

The combo row equals the plain h1-gated row: falling back to a 2- or 3-token head when the 1-token head
fails a gate rescues nothing that clusters (see §5). Per-file, the yield concentrates: reso
`settings.local.json` 285 exact → 92 newly dead from 18 prefixes; voiceink 43 → 26 from 4;
shadcn-pivot 154 → 25 from 7; claude-infrastructure local 52 → 23 from 4; cloud-agent 207 → 7 from 3
(its 181 `ssh -i` are uncoverable). Baseline before any consolidation: `dead_entries` already finds 254
dead in project files (183 of them in cloud-agent, shadowed by its own `Bash(ssh:*)`) and 145 in
worktree copies; 0 in the fleet.

Union-semantics deadness the per-file predicate deliberately does not assert (MEASURED under §5 union
+ §1 prefix semantics, `literal == base` counted as matched): 55 of 975 project exact entries are
already covered by a FLEET prefix (python3 14 — inert in auto mode, ls 7, grep 4, bun 3, git branch 3,
node -e 3 …); 183 of 390 worktree-copy exact entries are (reso's committed `Bash(pwd)`, `Bash(git
status)`, `Bash(git branch)`, `Bash(git stash list)`, `Bash(pnpm …)` ×37 copies). 154 of 2,513 project
allow strings are byte-identical to a fleet entry.

## 5. Gate hits over candidate heads (T5)

### T5 — gate hits over candidate heads

| head level | heads | auto-drop heads (entries) | ACE heads (entries) | PATH_BOUND heads (entries) | glob in head | ask/deny collision heads (entries) | pass-all heads (entries) |
|---|---|---|---|---|---|---|---|
| h1 | 204 | 10 (380) | 17 (223) | 86 (241) | 1 | 3 (276) | 104 (726) |
| h2 | 343 | 22 (349) | 69 (223) | 151 (201) | 4 | 4 (55) | 157 (601) |
| h3 | 383 | 58 (339) | 81 (186) | 227 (531) | 12 | - (-) | 128 (308) |


Entry-weighted, 1-token heads, all 1,365 exact entries (MEASURED): 726 pass; 639 fail at every head
depth. Why the 1-token head fails: PATH_BOUND slash 200 (+ tilde/tmp/`$` combos 40), AUTO_DROP ssh 181,
perl 82, bash 53, xargs 18, node 16, python3 15, curl 6, npx 4, zsh 4, bunx 1; ACE awk 8, source 5, bun 3,
`.` 2. **Rescue by depth:** 0 entries whose 1-token head fails are rescued by a passing 2-token head;
**2 entries** are rescued at 3 tokens (`npm run lint`, `npm run build` — `npm run` is auto-dropped, the
3-token form survives, exactly matcher-truth DO #2). PATH_BOUND at 1 token splits into 157 repo-relative
heads (`./scripts/deploy-parity-assert.sh`, `./bin/claude-accounts`, `.venv/bin/python`,
`scripts/generate-dev-guide.sh` …) vs 83 absolute/home/`$VAR` heads (`/usr/libexec/PlistBuddy`,
`"/Applications/Google Chrome.app/…"`, `$LSREGISTER`, `/Users/chrisren/.claude/scripts/…`) — and the
fleet already carries `Bash(scripts/ship-land.sh:*)`, i.e. a repo-relative script head is an accepted
fleet shape the gate as written would refuse.

## 6. Duplicates across files (T6)

### T6 — duplicates across files

allow entries total 8076 · distinct strings 2397 · strings present in ≥2 files 612 (6291 occurrences) — of which fleet-only 259, involving a project/worktree file 353, exact-Bash 69

| entry present in ≥2 non-fleet-only files | files |
|---|---|
| `Bash(git fetch:*)` | 69 |
| `Bash(shellcheck:*)` | 66 |
| `Bash(cat:*)` | 48 |
| `Bash(git add:*)` | 47 |
| `Bash(ls:*)` | 46 |
| `Bash(git diff:*)` | 45 |
| `Bash(git log:*)` | 45 |
| `Bash(jq:*)` | 45 |
| `Bash(git status:*)` | 44 |
| `Bash(node -e:*)` | 44 |
| `Bash(pwd:*)` | 44 |
| `Bash(basename:*)` | 43 |
| `Bash(dirname:*)` | 43 |
| `Bash(file:*)` | 43 |
| `Bash(head:*)` | 43 |
| `Bash(realpath:*)` | 43 |
| `Bash(stat:*)` | 43 |
| `Bash(tail:*)` | 43 |
| `Bash(wc:*)` | 43 |
| `Bash(git commit:*)` | 43 |
| `Bash(git push:*)` | 43 |
| `Bash(git stash:*)` | 42 |
| `Bash(git:*)` | 41 |
| `Bash(mkdir:*)` | 41 |
| `Bash(bash -n:*)` | 40 |

distinct exact literals 956 · embedding an absolute/`~`/`$HOME` path 636 · path-normalised (`<PATH>`) groups of ≥2 44 absorbing 228 literals · path+hex+num+uuid-normalised groups of ≥2 46 absorbing 232 literals

| path-normalised shape | literals | examples |
|---|---|---|
| `bash -n <PATH>` | 28 | `bash -n /Users/chrisren/Development/claude-infrast`; `bash -n /Users/chrisren/Development/claude-infrast`; `bash -n /Users/chrisren/Development/claude-infrast` |
| `perl -ne 'while \(<PATH>)<PATH>) { print "$1\\n" }' cli.js` | 25 | `perl -ne 'while \(/\(.{0,100}Ctrl.{0,5}C.{0,200}\)`; `perl -ne 'while \(/\(.{0,100}\\/exit.{0,300}\)/g\)`; `perl -ne 'while \(/\(.{0,100}appendFileSync.{0,200` |
| `perl -ne 'while \(<PATH>)<PATH>) { print "$1\\n---\\n" }'` | 21 | `perl -ne 'while \(/\(.{0,100}behavior..passthrough`; `perl -ne 'while \(/\(.{0,100}bypassPermissions.{0,`; `perl -ne 'while \(/\(.{0,100}dontAsk.{0,400}\)/g\)` |
| `cp <PATH> <PATH>` | 18 | `cp /Users/chrisren/.claude/commands/commit.md /Use`; `cp /Users/chrisren/.claude/hooks/validate-bash.sh `; `cp /Users/chrisren/.claude/settings.json ~/.claude` |
| `<PATH>` | 17 | `/Users/chrisren/.claude/hooks/session-save-id.sh`; `/Users/chrisren/.claude/hooks/setup-plan-symlinks.`; `/Users/chrisren/.claude/hooks/validate-bash.sh` |
| `mkdir -p <PATH>` | 9 | `mkdir -p /Users/chrisren/.claude-secondary/command`; `mkdir -p /tmp/advV/reso-management-app`; `mkdir -p /tmp/bm-test` |
| `git -C <PATH> status --short` | 9 | `git -C /Users/chrisren/Development/claude-infrastr`; `git -C /Users/chrisren/Development/natural-text-to`; `git -C /Users/chrisren/Development/natural-text-to` |
| `bash <PATH>` | 7 | `bash /Users/chrisren/Development/cloud-agent/scrip`; `bash /Users/chrisren/Development/cloud-agent/scrip`; `bash /tmp/count_tests.sh` |
| `gzip -c <PATH>` | 5 | `gzip -c /Users/chrisren/Development/shadcn-pivot-d`; `gzip -c /Users/chrisren/Development/shadcn-pivot-d`; `gzip -c /Users/chrisren/Development/shadcn-pivot-d` |
| `perl -ne 'print for <PATH>)<PATH>' <PATH>` | 5 | `perl -ne 'print for /\(.{100}effortValue:w.{300}\)`; `perl -ne 'print for /\(.{20}SLIDER_LEVELS.{250}\)/`; `perl -ne 'print for /\(.{30}BoY[\(=].{500}\)/g' /U` |
| `"<PATH> Chrome.app/Contents/MacOS/Google Chrome" \\
  --headless=new \` | 5 | `"/Applications/Google Chrome.app/Contents/MacOS/Go`; `"/Applications/Google Chrome.app/Contents/MacOS/Go`; `"/Applications/Google Chrome.app/Contents/MacOS/Go` |
| `git -C <PATH> status` | 4 | `git -C /Users/chrisren/Development/databricks-dais`; `git -C /Users/chrisren/Development/natural-text-to`; `git -C /Users/chrisren/Development/voiceink status` |
| `git -C <PATH> log --oneline -3` | 4 | `git -C /Users/chrisren/Development/databricks-dais`; `git -C /Users/chrisren/Development/voiceink log --`; `git -C /Users/chrisren/Development/voiceink-patche` |
| `"$LSREGISTER" -u <PATH>` | 3 | `"$LSREGISTER" -u ~/Downloads/VoiceInk.app`; `"$LSREGISTER" -u ~/Library/Developer/Xcode/Derived`; `"$LSREGISTER" -u ~/Library/Developer/Xcode/Derived` |
| `scp -i <PATH> <PATH> claude-agent@5.78.152.238:<PATH>` | 3 | `scp -i ~/.ssh/hetzner_claude_agent /Users/chrisren`; `scp -i ~/.ssh/hetzner_claude_agent /Users/chrisren`; `scp -i ~/.ssh/hetzner_claude_agent /Users/chrisren` |

(The path+hex+number+UUID-normalised table is identical to the above except for 2 additional groups — omitted; see `tables.md`.)


Without worktree copies (MEASURED): 2,382 distinct strings across fleet+project; 514 present in ≥2
files; 80 present in both a fleet file and a project file; 175 present in ≥2 project files (top:
`Read(//private/tmp/**)` 10, `Read(//tmp/**)` 9, `Bash(done)` 8, `Bash(git fetch:*)` 8, `Bash(open:*)`
8, `Bash(gh repo create:*)` 7, `Bash(git push:*)` 7 — note `Bash(git push:*)` is an ASK in the fleet, so
those 7 project allows are dead by precedence); only 20 exact Bash strings recur across ≥2 project files.
The F19 defect made visible: 636 of 956 distinct exact literals embed a path; path-normalising them
collapses 228 literals into 44 shapes (`bash -n <PATH>` 28, the two `perl -ne '…' <file>` shapes 25+21,
`cp <PATH> <PATH>` 18, bare `<PATH>` 17 — hook scripts run by absolute path, `git -C <PATH> status
--short` 9, `mkdir -p <PATH>` 9). Adding hex/number/UUID normalisation adds only 2 groups — the variance
is in PATHS, not in shas or pids.

## 7. `cc-permission-audit --prune` dry run (T7)

### T7 — `cc-permission-audit --prune` (dry run)

| run | scope files | dead / total (pct) | auto-mode dropped / total | rc |
|---|---|---|---|---|
| fleet 5 named explicitly | 5 | 0 / 1692 (0.0%) | 35 / 1692 | 0 |
| bare `--prune` (its own ~ walk) | 159 | 399 / 11322 (3.5%) | 586 / 11322 | 0 |

| fleet file | dead (prune) | auto-inert | auto-inert rules |
|---|---|---|---|
| `~/.claude/settings.json` | 0 | 7 | `Bash(bunx:*)` · `Bash(env:*)` · `Bash(node --version:*)` · `Bash(node -e:*)` · `Bash(python --version:*)` · `Bash(python3 --version:*)` · `Bash(python3:*)` · `Bash(bunx:*)` |
| `~/.claude-next/settings.json` | 0 | 7 | `Bash(bunx:*)` · `Bash(env:*)` · `Bash(node --version:*)` · `Bash(node -e:*)` · `Bash(python --version:*)` · `Bash(python3 --version:*)` · `Bash(python3:*)` · `Bash(bunx:*)` |
| `~/.claude-quaternary/settings.json` | 0 | 7 | `Bash(bunx:*)` · `Bash(env:*)` · `Bash(node --version:*)` · `Bash(node -e:*)` · `Bash(python --version:*)` · `Bash(python3 --version:*)` · `Bash(python3:*)` · `Bash(bunx:*)` |
| `~/.claude-secondary/settings.json` | 0 | 7 | `Bash(bunx:*)` · `Bash(env:*)` · `Bash(node --version:*)` · `Bash(node -e:*)` · `Bash(python --version:*)` · `Bash(python3 --version:*)` · `Bash(python3:*)` · `Bash(bunx:*)` |
| `~/.claude-tertiary/settings.json` | 0 | 7 | `Bash(bunx:*)` · `Bash(env:*)` · `Bash(node --version:*)` · `Bash(node -e:*)` · `Bash(python --version:*)` · `Bash(python3 --version:*)` · `Bash(python3:*)` |


MEASURED: bare `--prune` walks `~` to depth 5 and picks up 159 files (the 144 here plus 15 under other
`.claude*`-named dirs), 11,322 approved patterns, 399 dead (3.5%), 586 auto-dropped (5.2%). Named on the
five fleet files: 0 dead of 1,692; 35 auto-inert = the same 7 per file (`bunx`, `env`, `node --version`,
`node -e`, `python --version`, `python3 --version`, `python3`).

## 8. Consolidation ceiling

Population: **2,382 distinct allow strings** across fleet + project (2,123 project-only); 8,076 raw
entries including 87 worktree copies. The consolidation target is the **1,365 exact Bash entries** (975
project + 64 genuine worktree-local + 326 worktree copies of committed files); the fleet contributes
**0**.

| Step | Entries | Prefixes | Basis |
|---|---|---|---|
| Ungated, every 1-token head, project files | 606 collapse | 290 (191 heads) | T4 project row — the arithmetic maximum, includes `Bash(ssh:*)`, `Bash(perl:*)`, `Bash(bash:*)`, `Bash(do:*)` |
| Plan §3.2 gates, min-cluster 1 | 337 | 164 | one-shot prefixes wearing a `:*` — MIN_EVIDENCE would refuse most |
| **Plan gates, min-cluster 2 (the realistic ceiling)** | **254** | **58** | equal at h1 and combo; 4.4 entries retired per prefix |
| Plan gates, min-cluster 3 (plan step 8 wording "≥3 exact entries sharing a head") | 214 | 36 | 5.9 per prefix |
| + shell-KEYWORD gate (not in §3.2) | −40 to −71 | −8 | `do/done/for/[/#/set/export/while` heads pass every current gate and are nonsense as rules |
| + ASK_DENY_COLLISION as worded | −99 (`git`), −16 (`rm`) | −2 | refuses `Bash(git:*)` and `Bash(rm:*)`; 41 project/worktree files already carry `Bash(git:*)` |

Refused by construction, and permanently: `ssh -i …` 181 (auto-drop `ssh`), `perl -ne …` 82 (ACE +
auto-drop), `bash -n <path>` 31 + other `bash` 22 (ACE + auto-drop), `xargs` 17, `node` 16, `python3` 14,
`git -C <path> …` 82 (PATH_BOUND; the matcher cannot skip `-C`), absolute-path heads 73, repo-relative
script heads 63 (PATH_BOUND as worded). That is **≈580 of 975 project exact entries (≈60%) that no
gate-passing prefix can ever retire**; they can only be pruned as one-shots (which `--prune` deliberately
refuses to prove) or left. 3-token heads change the ceiling by 2 entries.

## 9. Design implications for the harvester

1. **Consolidation is a project-local operation, not a fleet one.** The fleet has 0 exact entries and 0
   dead entries; every consolidatable acceptance is in `~/Development/*/.claude/settings.local.json`
   (975) — files `cc-permission-audit --prune` will already rewrite under `CONFIRM=1` without naming
   them. Step 8 must therefore take project-local files as APPLY TARGETS (per-file, since the predicate
   proves deadness per file), or it consolidates nothing. Plan §3.3 currently names only
   `~/.claude*/settings.json` as targets. Conviction 95% (MEASURED: T1 aggregates).
2. **Drop 3-token heads from step 8; keep them only for step 5 (archive-driven candidates).** Over
   1,365 exact entries, a 3-token head rescues 2 (`npm run lint/build`), and the h1-gated yield equals
   the h1→h2→h3 combo yield at every min-cluster. The cost of 3-token support is 383 mostly-singleton
   heads (308 of 383). Conviction 90%.
3. **Add a SHELL_KEYWORD gate** (`do done then fi else for while until if [ [[ # set export case esac
   function` and the brace group openers): 73 entries (8 heads) pass every §3.2 gate and would mint
   `Bash(do:*)`. These are the F19 splitter's loop/test leaves; they are also the fingerprint of a saved
   compound whose other leaves are the real acceptance. Conviction 95%.
4. **Split PATH_BOUND into absolute-vs-repo-relative.** 157 of 241 path-bound 1-token heads are
   repo-relative scripts (`./scripts/x.sh`, `scripts/x.sh`, `./bin/x`) — a shape the fleet already
   accepts (`Bash(scripts/ship-land.sh:*)`) and reso's committed settings.json uses for 4 of its 6 exact
   entries. Refuse `/`, `~`, `$`, `tmp`, hex, digits; allow a head whose only slash is inside a
   `./`- or bare-relative script path. Conviction 80% — the residual question is whether a relative
   script prefix is "argument-constraining" in the F11 sense (it is not: the script IS the command).
5. **ASK_DENY_COLLISION must be one-directional.** As worded ("head is a prefix of … any deny/ask
   content") it refuses `Bash(git:*)` and `Bash(rm:*)` because `git push:*` is an ask and `rm -rf …` are
   denies — but deny→ask→allow precedence (§5) already makes the allow inert exactly on those
   sub-commands and live everywhere else, and 41 non-fleet files already carry `Bash(git:*)`. Refuse
   only when a deny/ask content is a prefix OF the candidate (`git push` under ask `git push:*`); when the
   candidate is a prefix of a deny/ask, PASS and state the carve-out in the receipt. Conviction 85%.
6. **The two big clusters are hook-layer, not rule-layer.** `ssh -i …` ×181 (one file, 181 distinct
   remote command lines) and `perl -ne '<regex>' <file>` ×82 are auto-dropped and ACE-refused; a
   `Bash(ssh:*)` already sits in that file and is what makes 183 of them "dead" today, yet each new ssh
   line still prompted and was saved. Report them in the STRUCTURAL/ACE bucket with their file, not as
   consolidation residue; and treat the `git -C <path>` 82 the same way (matcher cannot normalise it;
   authoring-habit lever: `cd`-less `git` in the worktree, or a hook). Conviction 90%.

Also worth carrying into plan §2: the "2,036 distinct patterns; 48% exact; 359 embedding an absolute
path" line is stale — today 2,382 distinct (fleet+project), 956 distinct exact literals, 636 embedding a
path; and the "5 forks" line should read "one-entry fork; deny/ask identical".

## 10. Open questions / caveats

* The normalisation applied here is a transcription of §1's `iae` reading, not the shared
  `hooks/lib/permission_matcher.py` (which does not exist yet, plan §4). 18 entries have raw ≠
  normalised head (env/wrapper prefix); 43 carry a foreign env prefix that iae will NOT strip for allow
  rules (F6) — a prefix on the bare command cannot cover them, and the predicate agrees.
* `wrapper` stripping of `timeout <dur>` / `nice -n N` argument shapes is INFERRED from probe D#13
  (`timeout 5 …`), not enumerated from the binary; 6 entries are affected.
* `ask/deny collision` was computed against the FLEET deny/ask union only; 23 deny + 16 ask strings
  exist only in project/worktree files and widen the set per cwd (listed in §2).
* Whether `Bash(x:*)` matches the bare command `x` (198 one-token literals) is asserted by matcher-truth
  §1 (`_ === g` ⇒ true) but not by the imported predicate; the yield tables follow the predicate.
