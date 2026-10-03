# Fleet instruction-load census (slug: fleet-census)

Date: 2026-10-03. Read-only. Everything below was produced by two re-runnable scripts:

    python3 /tmp/ibudget/collect_cwds.py 14   # -> /tmp/ibudget/cwds.json
    python3 /tmp/ibudget/census.py            # -> /tmp/ibudget/census.json, /tmp/ibudget/census-table.md

## 1. Method

**cwd list (measured):** `collect_cwds.py` scans `~/.claude*/projects/*` dirs with mtime < 14 days and takes the `cwd`
field from each transcript, so it does not depend on the lossy dir-name decoding. `~/.claude-next/projects` is a symlink
to `~/.claude/projects`, so the script dedups by realpath; without that, sessions were counted twice (first run:
5161 session files, deduped: 3847). It also takes live cwds from `lsof -a -d cwd -c claude -Fn`.
Result: `collect_cwds.py 14 => 2825 distinct cwds; 3847 session files; 20 live cwds`.

**Loader emulation:** `census.py` follows the 2.1.284 bundle (/tmp/cc284.strings, functions CRn/mY/$De/cet/yRn/ixt,
offsets ~20442000-20462000):
- User memory: `$CLAUDE_CONFIG_DIR/CLAUDE.md` plus unconditional `rules/**/*.md`.
- Walk: every dir from the one under `/` down to cwd. The bundle loop is
  `for(un=cwd; un!==parse(un).root; un=dirname(un)) gt.unshift(un)`, so `/` itself is excluded. In each dir it reads
  `CLAUDE.md`, `.claude/CLAUDE.md`, `.claude/rules/**` (rules with `paths:` are left out:
  `In.filter(Jn=>g?Jn.globs:!Jn.globs)`) and `CLAUDE.local.md`.
- Dedup by path and symlink-resolved path.
- Counted content is the body after frontmatter, with HTML-comment blocks stripped (`vbe`), measured as UTF-16 length.
- @-imports use the bundle regex `(?:^|\s)@((?:[^\s\\]|\\ )+)` outside code, depth < 5. **No real @-imports exist
  in any scanned file.** The only `^@` line is `@keyframes` in reso `view-transitions.md`, which is conditional and
  does not resolve to a file.
- **The live `claudeMdExcludes` in `~/.claude/settings.json:1313` is applied:**
  `["**/.claude/rules/agent-operating-lessons-situational.md"]`. Without it the numbers come out wrong (for example,
  claude-infrastructure would include a 73.6k file that is in fact excluded).

**Validation (measured):** the emulated reso-management-app scenario A gives **9 files, 428,086 chars ("428.1k")**,
with the largest files at 151.7k / 111.6k / 57.1k. This matches the startup warning that triggered this task exactly.

**Warning semantics (from the bundle, `ixt`/`ARn`):**
- Per-file limit `hVe = max(40000, window*0.05*3)`; total limit `iRn = max(120000, hVe)`.
- The total-over warning sums only files at or under the per-file limit:
  `n.reduce((h,b)=>b.content.length>r.limitChars?h:h+b.content.length,0) <= totalLimitChars`.
- So on a 200k window, files over 40k raise per-file warnings but are not counted toward the 120k total.

## 2. Census table (measured by census.py, slim account profile = all 4 account dirs)

Scenarios:
- **A:** as today.
- **B:** A minus the ancestor-loaded `~/.claude/CLAUDE.md` and `~/.claude/rules/**`.
- **C:** B with the reso `bottle-generation-ledger.md` cut to 6k.

"Sessions 14d" counts transcript files. "Live" counts distinct live cwds.

| repo | sessions 14d | live cwds | A | B | C | files >40k (A) | top 3 (A) | C >150k | C >120k |
|---|---|---|---|---|---|---|---|---|---|
| ~/Development/reso-management-app (+ its .worktrees) | 130 | 5 | 428.1k (9 files) | 307.4k | **161.7k** | ledger 151.7k; ~/.claude/CLAUDE.md 111.6k; slim 57.1k; agent-operating-lessons 52.1k | ledger 151.7k; ~/.claude/CLAUDE.md 111.6k; slim 57.1k | **YES** | **YES** |
| ~/Development/reso-qa-runner (worktree of reso) | 12 | 0 | 428.1k | 307.4k | **161.7k** | same as above | same | **YES** | **YES** |
| ~/Development/reso-management-app-release (0 sessions in 14d; computed directly) | 0 | 0 | 401.9k | 281.2k | **161.7k** | ledger 125.5k; full 111.6k; slim 57.1k; lessons 52.1k | ledger 125.5k; full 111.6k; slim 57.1k | **YES** | **YES** |
| ~/Development/personal (rep cwd launch-film-2026/studio) | 62 | 1 | 233.6k | 112.9k | 112.9k | full 111.6k; slim 57.1k; personal agent-operating-lessons 51.9k | full 111.6k; slim 57.1k; lessons 51.9k | no | no (7.1k headroom) |
| ~/Development/claude-infrastructure (+ worktrees) | 686 | 9 | 196.7k | 76.0k | 76.0k | full 111.6k; slim 57.1k | full; slim; .claude/rules/agent-operating-lessons 9.7k | no | no |
| ~/.claude/** (autonomy eval fixtures) | 161 | 0 | 196.6k | 75.9k | 75.9k | full; slim | full; slim; fixture lessons 9.7k | no | no |
| ~/Development/reso-web-app | 11 | 0 | 195.1k | 74.5k | 74.5k | full; slim | full; slim; CLAUDE.md 13.7k | no | no |
| ~/Development/voiceink | 9 | 1 | 183.5k | 62.9k | 62.9k | full; slim | | no | no |
| ~/Development/sevenrooms-bridge | 21 | 1 | 181.4k | 60.8k | 60.8k | full; slim | | no | no |
| agent-context-sync, doc_classifier, claude-private, fde-endpoint-business-case, natural-text-to-voice-extension, pyramid-principle-full, tm-upstream-clone, ~ , ~/Development, ~/.cache/*, deleted worktrees (repo unknown, 11) | 1-15 each | 0-1 | 180.7k | 60.0k | 60.0k | full; slim | | no | no |
| tmp / eval-harness dirs outside $HOME (/private/tmp, /private/var/folders) | 2689 | 1 | 60.0k typical; max 177.1k | same | same | (6 sessions in tokeff-gate fixtures with a 108k fixture .claude/CLAUDE.md copy) | | 6 sessions YES (fixtures, not prod) | |
| undecoded project dirs (no cwd in transcript) | 5 | | n/a | | | | | | |

Full per-file lists for every row are in `/tmp/ibudget/census.json` (keys `A/B/C.files`).

**Baseline every session in $HOME pays today (measured):**
- slim user memory: 57.1k + 2.9k.
- Plus ancestor `~/.claude/CLAUDE.md` 111.6k and `~/.claude/rules/*` 9.1k, which together come to **180.7k**.

So **every session under /Users/chrisren is over 150k in scenario A**, whatever the repo. The `>150k` count in A covers
all repo buckets: 686 + 161 + 130 + 62 + ... sessions. Outside $HOME (/private/tmp evals) the load is 60.0k because the
ancestor walk never reaches `~/.claude`.

**Default-config profile (CLAUDE_CONFIG_DIR unset, so user memory is `~/.claude/CLAUDE.md` full):**
- A is 120.7k base; reso is 368.1k.
- The profile exists: `~/.claude/projects` holds 14-day transcripts, but they cannot be told apart from
  `.claude-next` because the projects dir is shared through a symlink.
- The `claudeMdExcludes` matcher does not look at memory type (bundle:
  `(g==="User"||g==="Project"||g==="Local")&&r(path)`). If B is done with excludes, those sessions would lose the global
  file entirely: base drops to 0.0k global, and claude-infrastructure falls to 16.0k
  (`census.json` key `B_default_cfg_total_if_exclude_glob_is_typeblind`).

## 3. Repos still over the limits under C

Only the reso family: **reso-management-app, reso-qa-runner, reso-management-app-release (and every reso worktree) = 161.7k**
(measured). It is over both 150k and 120k:

| file | chars (C) | share |
|---|---|---|
| ~/.claude-<acct>/CLAUDE.md -> CLAUDE.slim.md (User) | 57,137 | 35% |
| reso `.claude/rules/agent-operating-lessons.md` | 52,091 | 32% |
| reso `CLAUDE.md` | 35,898 | 22% |
| reso `.claude/rules/agent-teams.md` | 7,673 | 5% |
| bottle-generation-ledger.md (assumed 6k) | 6,000 | 4% |
| rules.slim/00-mission-board.md | 2,883 | 2% |

- To get under 150k it needs at least 11.7k more cut; under 120k, at least 41.7k (arithmetic on the measured totals).
- The single biggest repo-side lever is reso `agent-operating-lessons.md` (52.1k, always loaded, no `paths:`).
- On a 200k-window model, two files would still raise per-file warnings under C: the slim user file (57.1k > 40k) and
  reso lessons (52.1k). Because the total check sums only files under 40k (52.5k < 120k), that model would show
  per-file warnings but no total warning.

**Closest to the edge:** `~/Development/personal` at 112.9k under C. It is under 150k and 120k, but personal
`agent-operating-lessons.md` (51.9k) is over the 40k per-file limit on 200k windows, and headroom to 120k is only 7.1k.

**Per-file >40k under C, fleet-wide:** the slim user file (57.1k) is in every session, so every 200k-window session
gets a per-file warning even in scenario C. Transcripts from the last 3 days show `claude-haiku-4-5` in 174 transcript
files (measured by a regex count of "model" over ~/.claude-*/projects jsonl, mtime < 3d). That is a 200k-window model,
but whether those are main sessions or subagents was not determined.

## 4. Caveats (inferred vs measured)

- Deleted worktrees (279 cwds) are matched to a repo by the most-mentioned `/Users/chrisren/Development/<repo>` in their
  transcript, then emulated at the main checkout. That is a heuristic, and branch contents may have differed.
- The representative cwd per repo is the one with the largest A load. Most repo buckets have identical loads across
  their cwds; personal varies by subdir.
- HTML-comment stripping and YAML `paths:` parsing are approximations of marked/As. The 428,086 vs "428.1k" match
  supports that the approximation is accurate.
- Window size per session is not measured. The 150k/120k columns are reported for both windows.
- Symlink-dedup idea (inferred, untested): if `~/.claude/CLAUDE.md` were itself a symlink to `CLAUDE.slim.md`, the
  ancestor load would dedup against the account's user memory by resolved path (`if(ge){Ee=Gp(Y);if(r.has(Ee))return[]}`).
  That would fix B without a type-blind exclude. It depends on the `ZL`/isCanonical symlink gate, which was not verified.
