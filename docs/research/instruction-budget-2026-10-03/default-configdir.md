# default-configdir: is `claudeMdExcludes` safe in the shared `~/.claude/settings.json`?

Slug: default-configdir. Worker: read-only, 2026-10-03 ~14:40 CDT. The only file written is this one.

## Verdict

**NEEDS-launcher-injection.** Putting
`["/Users/chrisren/.claude/CLAUDE.md","/Users/chrisren/.claude/rules/**"]` in the shared
settings is unsafe as things stand. Shared settings would only become safe if `~/.claude` were
formally retired as a session config dir and a guard enforced that (see Option B).

Why:
1. The matcher does not care about memory type, and it compares the same spelling. A session with
   the default config dir loads its USER memory from exactly `/Users/chrisren/.claude/CLAUDE.md`
   and `/Users/chrisren/.claude/rules/*.md`. The exclude would remove all global instructions from
   that session without any warning.
2. Arrays from settings sources are CONCATENATED, and that includes `--settings`. A launch that
   needs the full file therefore has no way to opt back in. A user-level exclude cannot be undone
   per launch.
3. The default dir is dormant now, but it has not been removed. `claude-prev` (unset → `~/.claude`),
   the `cc()` fallback, and any launchd job with no `CLAUDE_CONFIG_DIR` that runs `claude` with
   user settings all land on it.

## 1. Census of launch paths (measured unless marked)

| Path | Config dir | Binary | Through `cc-close-attrib`? | Evidence |
|---|---|---|---|---|
| `claude` (router) / `claude1` | routed account or `~/.claude-next` (default when unset) | `~/.claude-284/.../claude` | YES | `~/.zshrc:479` `_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"`; `~/.zshrc:502-508`; `lib/claude-launcher.zsh:230-259`; `account-map.generated.sh` maps only next/next2/3/4, never `~/.claude` |
| `claude2/3/4`, `cc2/3/4` | `~/.claude-secondary/-tertiary/-quaternary` | same | YES (via `claude`) | `lib/claude-launcher.zsh` / `~/.zshrc:241,257,270` |
| `claude-prev` | **unset → `~/.claude` (DEFAULT)** | `claude-latest` → `~/.claude-versions/current` = 2.1.114 | NO | `~/.zshrc:171` `_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"`, `:179,181` |
| `claude-prev2/3/4` | account dirs | 2.1.114 | NO | `~/.zshrc:185-187` |
| `cc` fallback | can pin `CLAUDE_CONFIG_DIR=$HOME/.claude` | `claude` → wrapper | YES, but in the default dir | `~/.zshrc:526-545` (`for dir in "$config_dir" "$HOME/.claude"`) |
| `_cc_resume_pin` | sets `CC_RESUME_CFG` only when projects realpaths differ | – | YES | `lib/cc-resume-shell.sh:118-129`; `~/.claude-next/projects -> ~/.claude/projects`, so a `~/.claude` session resumes under `.claude-next` |
| handoff-fire typed launches | pinned account (`CC_ACCOUNT_PINNED=1`) | launcher fns | YES | `scripts/handoff-fire.sh:13429-13430` |
| handoff-fire liveness probe | account dir, `cd /tmp`, `-p` | `$BIN` | NO, but cwd is /tmp so no ancestor walk | `scripts/handoff-fire.sh:12924-12927` |
| limit-recover resume (`expect`) | account (`LR_CFG`) | wrapper | YES | live: 5 `expect` parents → children `bash cc-close-attrib ... --resume`, all `CLAUDE_CONFIG_DIR=~/.claude-quaternary`; `scripts/limit-recover/lr-fire-resume.sh:759` |
| reso qa-nightly (launchd) | `~/.claude-next` (since 2026-09-20; before that **unset/default**) | `~/bin/claude-latest` 2.1.114, cwd `~/Development/reso-qa-runner` | NO | `~/Library/LaunchAgents/com.reso.qa-nightly.plist:24`; reso-qa-runner `1afa4c8f8` comment: "default config dir's expired OAuth token 401s every night; hand-edited into the live plist on 2026-09-20"; `scripts/qa-commits-nightly.ts:193,327-328` (`env: {...process.env}`) |
| cc-memory-extract, model-permission-decider | inherit | resolver / `claude -p` | NO | `--setting-sources ""` (`bin/cc-memory-extract:375-376`; `hooks/model-permission-decider.py:68,422`), so CC loads NO user/project memory (see §2) |
| research-kit classifier | inherit / launchd unset | bare `claude` = `/opt/homebrew/bin/claude` 2.1.278 | NO | `scripts/research-kit/router.py:228-233` `--setting-sources local`, cwd an empty dir, so no user memory |
| CC daemon bg spares | `~/.claude-next` | `claude.exe --bg-spare` | NO (argv has no `--settings`) | live PIDs 8514/8751/9780/10027/10156; `ps -o args=` shows no `--settings` |
| 47 launchd agents | all except qa-nightly have **no** `CLAUDE_CONFIG_DIR` | various | – | `plutil` sweep of `~/Library/LaunchAgents/*.plist` (§ command below); none found to exec a session binary directly besides qa-nightly, but every one would inherit the DEFAULT dir if it did |
| crontab | – | – | – | `crontab -l` → 1 entry, `mb-hpc-price-watch` (not Claude) |

Live processes (measured, `ps -axo pid,args | grep claude` and then `ps eww -p PID` per PID; rows in
`/tmp/ibudget/live-procs.tsv`): 51 claude-related PIDs. By `CLAUDE_CONFIG_DIR`: quaternary 32,
tertiary 8, next 5, plus 5 `expect` parents whose children are quaternary. The 1 "unset" is a `cp -Rc
~/.claude …/gate-home.*/.claude` (upgrade-gate hermetic HOME), not a session.
**0 live session binaries use the default dir.** 19/19 live `.claude-284/.../claude` binaries carry an
injected `--settings` (17 `{"autoMemoryDirectory":…}`, 2 also `disabledMcpjsonServers`).

Recent history (measured):
- `~/.claude.json` is the state file of an unset `CLAUDE_CONFIG_DIR`. `numStartups` = 1762, identical to
  `~/.claude.json.bak-tenantfix` (2026-08-23). So there have been **no interactive default-dir
  startups since at least 2026-08-23** (python diff of the two files). It still changed later: mtime
  2026-09-30 15:30, `migrationVersion` 11→14, new project keys `/` and `reso-qa-runner`, and
  `skillUsage.qa-commits` lastUsedAt 2026-09-20 19:39. Those are headless default-dir runs
  (qa-nightly until 2026-09-20; whatever wrote 09-30 is unidentified).
- `~/.claude/.claude.json` (explicit `CLAUDE_CONFIG_DIR=~/.claude`): numStartups 10, mtime 2026-09-24.
  Its project keys are bats/tmp/upgrade-gate dirs, i.e. test harnesses.
- Transcripts cannot be attributed by directory. `~/.claude-next/projects`, `session-env`,
  `file-history`, `todos`, `sessions` and `history.jsonl` are all symlinks into `~/.claude`.
  `find ~/.claude/projects -maxdepth 2 -name '*.jsonl' -mtime -14` → 1317, a mix of next and
  default. Their `version`s: 2.1.280/284 = 1070 (wrapper track); 2.1.114 sdk-cli = 147 (133 in
  /private/tmp, 12 reso-qa-runner, 2 worktrees); 2.1.278 sdk-cli (homebrew bare `claude`) = 72 (9
  with cwd under `~/.claude/autonomy/memory-eval-bench`); 2.1.260 cli = 26 (older wrapper sessions).
  The 2.1.114 and 2.1.278 runs did not go through the wrapper.

## 2. CC 2.1.284 internals (from `/tmp/cc284.strings`, python search)

- Exclude matcher `yet()` (offset ~20455735): `e=Qe().claudeMdExcludes` (merged settings), patterns
  expanded by `kRn(le(),e)`, then `picomatch(n,{dot:true})`.
  `return (s,g)=>(g==="User"||g==="Project"||g==="Local")&&r(s.replaceAll("\\","/"))`. This is
  type-blind (confirmed).
- **Symlink vs realpath:** both are covered.
  - `kRn` takes each absolute pattern's non-glob prefix and resolves it with `xo()` (the realpath).
    If that differs, it appends a realpath-prefixed copy of the pattern. Patterns therefore match
    both spellings of their own prefix.
  - Top-level memory files go through `ket(e)` → `_et(e,…)`, where `e` is the SPELLED path the
    walker built. Examples: `xf(un,".claude","CLAUDE.md")` in the ancestor walk; `Q7("User")` =
    `$CLAUDE_CONFIG_DIR/CLAUDE.md` for user memory.
  - Rules dirs (`$De`) check the spelled `Vt=(discoveredDir??e)/name` when it differs from the
    realpath `Dt`, then call `mY(Dt,…)`, which checks the REALPATH. Either match excludes the file.
  - Consequences for the proposed patterns: `~/.claude-<acct>/CLAUDE.md` (a symlink to
    `CLAUDE.slim.md`) does NOT match. `~/.claude-<acct>/rules/00-mission-board.md` (realpath
    `~/.claude/rules.slim/…`) does NOT match `/Users/chrisren/.claude/rules/**`, because the segment
    `rules` ≠ `rules.slim`. `~/.claude/CLAUDE.md` and `~/.claude/rules` are regular files/dirs
    (`stat`: nlink 1, not symlinks), so `kRn` adds no extra patterns.
- Loader `CRn` (offset ~20463000):
  - User memory loads only if `Pe=lr("userSettings")`.
  - The project walk runs only if `gv("projectSettings")`. Its `projectFiles` list is pre-filtered
    by `_e(path,"Project")`, using the spelled path.
  - Dedup goes through the shared `processedPaths` set. In a default-dir session the User load of
    `~/.claude/CLAUDE.md` happens first, so the Project walk's hit is deduped. With the exclude,
    BOTH are dropped and the session gets zero global instructions.
  - `--setting-sources ""`/`local` disables User memory (and `""` disables the project walk too),
    so those headless callers are unaffected either way.
- **`--settings` vs userSettings arrays:** the merge customizer is
  `i9(e,n,s){… if(Array.isArray(e)&&Array.isArray(n)){if(s==="fallbackModel")return n;return M([...e,...n])} …}`
  (offset 13083836). `JYn` applies it across every source, including `flagSettings`. So the arrays
  MERGE (union, deduped). An injected list is added to the existing user-level
  `["**/.claude/rules/agent-operating-lessons-situational.md"]` and cannot remove it.
- **Only one `--settings` counts:** `ON(n,e)=kue(n,e).at(-1)` (offset 13797963) means the last
  occurrence wins. A second `--settings` flag would silently drop the wrapper's `autoMemoryDirectory`.
  The new key must be merged into the same JSON value.
- Teammates inherit `--settings`: the tmux teammate argv builder does
  `let T=g0()??E1();if(T)r.push(\`--settings ${…}\`)` (offset 44158594). This is inferred to be the
  launch's flag settings.
- bg daemon: spares are pre-spawned with no `--settings`. The strings `extra_args_mismatch_reboot` /
  `respawnFlags` suggest a claim that carries different args reboots the spare with them. **Not
  verified.**
- 2.1.114 (stable track) also contains the string `claudeMdExcludes` (5 hits, `grep -a -c`). Its
  semantics were not verified, and it is below the 2.1.239 fix for "claudeMdExcludes not excluding
  a symlinked .claude/rules" (`docs/research/cc-version-audit-2026-09-08.md:147`).

## 3. Injection site

`bin/cc-close-attrib` (deployed `~/.claude/bin/cc-close-attrib`), `_memdir_inject` at lines 59-160.
It runs after `REAL_BIN` is shifted off, and edits `BIN_ARGV` into `MEMDIR_ARGV`. It either prepends
`--settings={"autoMemoryDirectory":…}` or merges into one existing `--settings` (inline JSON, or the
contents of a file, inlined). It never adds a second flag, and it refuses when there are 2+
`--settings`. Every `claude()` launch goes through it: `~/.zshrc:505,508`
`"$HOME/.claude/bin/cc-close-attrib" "$_bin" …`. So does lr-fire-resume (`LR_WRAP`).

Constraints for adding `claudeMdExcludes` there:
- Make it an INDEPENDENT step, not a branch of `_memdir_inject`. That function returns early when
  `CLAUDE_CONFIG_DIR` is unset, for bare/submodule repos, for non-ASCII roots, for slugs over 200
  chars, and whenever `real == spelled` (no symlink, e.g. a fresh project dir on secondary/tertiary/
  quaternary whose `projects/` is a real dir with 0 symlinked slugs:
  `find ~/.claude-{secondary,tertiary,quaternary}/projects -maxdepth 1 -type l | wc -l` → 0 each).
  Tying the exclude to those conditions would give patchy coverage.
- Gate it on `realpath($CLAUDE_CONFIG_DIR) != realpath($HOME/.claude)`, and skip it when the var is
  unset (the default dir).
- `_memdir_merge` assumes its key is absent. The new merge must union with any `claudeMdExcludes`
  already present inside the `--settings` JSON, because duplicate JSON keys are last-wins under
  `JSON.parse`.
- `hooks/lib/rules-loaded.sh:17-26` reads `claudeMdExcludes` ONLY from `~/.claude/settings.json`, so
  it would not see an exclude injected by the launcher. That is acceptable, because its question is
  about `.claude/rules` files inside a repo, but the scope note should mention it.

## 4. Coverage gaps of launcher injection (paths that still double-load the full file)

1. reso qa-nightly: daily around 04:2x, 2.1.114, `CLAUDE_CONFIG_DIR=~/.claude-next`, cwd under home,
   not wrapped.
2. `claude-prev2/3/4`: an account dir, cwd under home, not wrapped.
3. Bare homebrew `claude` (2.1.278) headless runs with user settings on and cwd under home (e.g. the
   memory-eval bench in `~/.claude/autonomy/...`).
4. CC daemon bg sessions claimed from spares, if the claim does not carry the claimant's
   `--settings` (unverified).
Shared settings would cover all four automatically. That is the trade-off.

## 5. Options

- **A (recommended): inject in the launcher.** Add `claudeMdExcludes` in `cc-close-attrib` as
  described in §3. Also close gaps 1-3:
  - give qa-nightly's `claude-latest` call the same `--settings` (or route it through
    `cc-close-attrib`);
  - route `claude-prev2/3/4` through the injector, or retire them;
  - list bare `claude` under home in the unattended-path lint.
  - For gap 4, probe a bg job's argv once.
- **B (only if the operator retires the default dir):** put the exclude in shared settings, and add a
  SessionStart guard that refuses or loudly warns when `CLAUDE_CONFIG_DIR` is unset or equals
  `~/.claude`. Also give `claude-prev` an explicit account dir. The guard must exist, because the
  exclude cannot be undone per launch (arrays union).
- **C (unverified idea, outside this brief):** make `~/.claude/CLAUDE.md` itself the slim copy (or a
  symlink to it). The Project walk would then be deduped through `processedPaths` and the realpath,
  on every launch path. The cost: default-dir sessions would also get slim instead of full. Needs a
  probe, because of `ZL()`/`isCanonical` and the User-symlink skip rule in `mY`.

## Commands used (selection)
- `ps -axo pid,ppid,etime,args | grep -E 'claude…'` then `ps eww -p PID | tr ' ' '\n' | grep ^CLAUDE_CONFIG_DIR=` → `/tmp/ibudget/live-procs.tsv`
- `plutil -convert json` over `~/Library/LaunchAgents/*.plist` (ProgramArguments + EnvironmentVariables.CLAUDE_CONFIG_DIR)
- python diff of `~/.claude.json` vs `~/.claude.json.bak-tenantfix`; key/timestamp reads of `~/.claude/.claude.json`
- `find ~/.claude*/projects -maxdepth 2 -name '*.jsonl' -mtime -14` + per-file `version`/`entrypoint`/`cwd` (list in `/tmp/ibudget/recent-default-tx.txt`)
- python `str.find`/`re.finditer` on `/tmp/cc284.strings` for `claudeMdExcludes`, `function kRn(`, `function mY`/`$De`/`CRn`, `function i9(`, `function ON(`, `"--settings"`
- Keychain metadata read of the default-dir credential was DENIED by the auto-mode classifier. So "default dir is unauthenticated" rests only on the reso-qa-runner commit text (2026-09-20) and is unverified today.
