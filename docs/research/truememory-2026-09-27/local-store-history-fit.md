# local-store-history: FIT AND COST lens (2026-09-27)

## Measured facts
- Physical non-empty stores: 39. Measured by resolving every <cfg>/projects/*/memory with `pwd -P` across the 4 config dirs and deduping. All 39 sit under /Users/chrisren/.claude/projects. The .claude-next projects dir is a symlink to it, and the memory dirs in the secondary, tertiary and quaternary accounts resolve there too.
- Raw size of all stores: 12,572 KB (du -sk, summed). Largest by file count: reso-management-app (840 files, 2.1 MB gzipped tar) and claude-infrastructure (498 files, 3.3 MB, 1.1 MB gzipped tar; tar|gzip -6|wc -c).
- `git hash-object --stdin-paths` over the 519 files of the claude-infrastructure store: 0.15 s cold, 0.02-0.03 s warm (/usr/bin/time -p). A `git commit` benchmark in a /tmp scratch repo was refused by the PreToolUse shared-checkout gate, and worker rules forbid commits, so commit cost is ESTIMATED at 50-150 ms (hash cost plus 3-4 git process spawns).
- Mutation frequency: archive/.rotate.log in the busiest store has 30 lines, the last on 2026-09-22 (wc -l, tail). Rotation is rare, although the rotor is invoked on every prompt (memory-fleet-sweep.sh:5, "invoked from hooks/memory-nudge.sh on every prompt").
- No undo exists today:
  - The restic job's SOURCE is only $HOME/.claude/archives/claude-code/ (restic-claude-archive-backup.sh:58).
  - Time Machine includes ~/.claude/projects (`tmutil isexcluded` returns [Included]), but its Local destination cannot mount: `tmutil latestbackup` gives "Failed to mount destination ... Code=18" and `listbackups` gives "No machine directory". TM has made no backups.
  - The main store has 19 PRE-COMPACT snapshots. The fleet-wide count of 200 is the same 19 seen again through worktree memory symlinks. These snapshots cover MEMORY.md only, not topic files (commands/compact-memory.md:121,264).
- Neither the stores nor ~/.claude are inside a git repo (`git -C ... rev-parse` returns fatal).
- The target file bin/cc-memory-forget DOES NOT EXIST (ls).
- The "1,461 lines destroyed" incident was a MAILBOX store (deskA.md mv -f overwrite), not a memory store: memory append-only-store-safety-rules.md, rule 2. Plan R2 cites it as the same hazard class.

## Refutations and costs of the proposal as written
1. A .git INSIDE each store collides with our tooling:
   - lib/config-mirror.zsh:255 merges a real account memory dir into canonical with `rsync --ignore-existing` (--convert), and the adopt branch moves whole dirs (:290). Two .git dirs would be merged file-by-file, keeping one HEAD/index and mixing objects.
   - Worktree stores are symlinks (scripts/worktree-memory-link.sh), so there are ~160 alias paths to the same .git.
   - The model's Glob/Grep over the memory dir would see object files.
   - Most of our scans are safe because they use -maxdepth 1 or *.md globs: cc-memory-rotate:339,1018,1060 and jev/promote-memory.sh:290.
   Fix: keep the history OUTSIDE the store with --git-dir=$HOME/.local/state/cc-memory-history/<slug>.git --work-tree=<realpath store>, keyed by the physical slug.
2. The nightly launchd commit conflicts with a recorded operator constraint. memory-fleet-sweep.sh header: "deliberately does NOT install a background job: rotating memory files with no session watching is a class of automation the operator constrains". Drop it. A pre-image commit inside each automation already sweeps up all model writes made since the last commit, which is exactly the R2 hazard (automated mutation). Model-only clobbers stay uncovered unless an optional detached SessionStart snapshot of the session's own store is added.
3. "lockf fd lock": the rotor's lock is mkdir-based (cc-memory-rotate:115, "macOS has no flock(1)"). Git's own index.lock is the real hazard. memory-index-drain is PostToolUse with timeout 10 (settings.json:529-530), so a SIGKILL mid-`git add` leaves a stale index.lock that SILENTLY disables all later snapshots. Fix: use a per-run mktemp GIT_INDEX_FILE, then `add -A`, `write-tree`, `commit-tree`, and `update-ref refs/heads/main NEW OLD` (compare-and-swap, retry once). Then no persistent lock can go stale.
4. Hermeticity: derive the history root from $HOME so the hermetic-$HOME bats suites (cc-memory-rotate.bats, memory-index-drain.bats, config-mirror-memory-adopt.bats) contain it automatically. A new CC_* seam must be pinned in setup() per test-hermeticity-lint rules 5 and 6. Snapshot failure must never fail the caller.
5. Forget semantics: history keeps anything deleted forever. A secret written by mistake would need a purge path (`rm -rf` the store's gitdir, or reflog expire + gc).
6. The marginal benefit for the rotor is lower than claimed. Its moves are already verbatim, verified and reversible (cc-memory-rotate:109-118). The real beneficiaries are compact-memory (an LLM rewrite of topic files) and the not-yet-built capture/supersede/forget automations that R2 blocks.
7. History alone does not lift R2. It is a policy stance ("every mechanism in this plan is read-only against the store") and remains the operator's call. History is necessary, not sufficient.

## Cost estimate (ESTIMATED)
- Build: about 120 lines of bash (scripts/memory-store-snapshot.sh), about 12 bats cases, and 3 call sites (rotor mutation branch, compact-memory step, future forget/supersede). Size S-M, 1-2 sessions.
- Runtime: 0 ms on the common path, because it runs only inside a mutation branch. 50-150 ms per mutation, which is well under the drain's 10 s. No daemon, no memory pressure.
- Disk: under 10 MB/yr across all stores, based on the 12.5 MB raw total, about 3:1 zlib, and deltas written only per mutation.
