# Gap G1: the temp-slug skip has to be a glob exclusion, not a `case` skip

Read-only. Nothing in the repo or in any account dir was changed. No hook was run.

## 1. The defect in the README

- README.md:158 (Wave 1.1) allows two forms: exclude temp slugs "from both globs (local `setopt extendedglob` under `emulate -L zsh`, **or a `case` skip at the top of the `:302` loop**)".
- The two forms are not equal. Under a `case` skip, both full globs at `lib/config-mirror.zsh:300-301` still run. Each one stats about 18k entries for the `/` qualifier, and the code still builds the ~18.9k-key `slugs` hash before the loop reaches the skip.
- README.md:229 already says "A per-slug filter still pays the 18k-entry globs". So §6 contradicts the second form that §5 allows.
- At load 505-534, A2 M4 (A2-child-cost.md:44) measured the globs plus hash inserts at 2,215 + 6,822 = 9,037 ms of a 13,830 ms walk [M, A2]. That is above the 9 s child bound on its own.

## 2. Re-measurement (this session)

[M: inline zsh function `walk` in this session: `emulate -L zsh; setopt extendedglob`, `$EPOCHREALTIME` around each phase, link check with `zstat -L +link`. It is the same logic as `a2-memmirror-scan.zsh`, and it only counts mutating branches. Two reps × 3 accounts × 3 variants, interleaved. `sysctl -n vm.loadavg` was 130.25 before and 133.07 after.]

Variants: `full` is today's code. `excl` uses `"$cano"/^(-private-var-folders-*|-private-tmp*)(N/)` and the same pattern for dst. `case` keeps the full globs and adds `case $slug in (-private-var-folders-*|-private-tmp*) continue;; esac` at the top of the loop.

| account | rep | full ms (keys) | excl ms (keys) | case ms: globs+hash / loop | case as % of full | excl as % of full |
|---|---|---|---|---|---|---|
| quaternary | 1 | 4,102 (18,933) | 394 (1,405) | 5,421 / 510 = 5,931 | 145 % (first-run noise) | 10 % |
| secondary | 1 | 6,119 (18,968) | 903 (1,409) | 3,834 / 276 = 4,110 | 67 % | 15 % |
| tertiary | 1 | 7,325 (18,938) | 691 (1,461) | 3,397 / 294 = 3,690 | 50 % | 9 % |
| quaternary | 2 | 5,615 | 607 | 3,543 / 307 = 3,850 | 69 % | 11 % |
| secondary | 2 | 5,267 | 626 | 2,858 / 441 = 3,299 | 63 % | 12 % |
| tertiary | 2 | 4,977 | 612 | 3,864 / 413 = 4,276 | 86 % | 12 % |

- The `case` form keeps 50-86 % of the walk (median of the five clean pairs is 67 %) [M, above]. In every case run, 87-93 % of the cost was the globs plus the hash.
- The `excl` form keeps 9-15 %, which is 0.39-0.90 s at load ~130 [M, above]. The brief's earlier probe measured 273 ms for `excl` and 1,586 ms for `case` at load 99-133 [M, brief].
- My `full` times (4.1-7.3 s) run higher than the A8 skeptic's replica (1.69-3.70 s at load 112-125, A8-precompute-load.md:531). Both are at moderate load, so the absolute figures are noisy. The ratios are what matter here.

**New finding.** All of the per-start mutation work is in temp slugs [M, same runs, branch counters]:
- With `full`, the walk would link 31 slugs on quaternary and 25 on secondary, and quaternary also has 6 real-dir (adopt) slugs.
- With `excl`, every one of those counters is 0. The 127-129 non-temp slugs per account are all already linked.
- The A8 skeptic credits this mutation work with the rest of the isolated-versus-shared gap (A8-precompute-load.md:531-534: secondary 22 creates and 14 wrong targets, quaternary 28 creates and 4 adopts). Each pending link costs `rm`, `mkdir -p` and `ln` forks (`lib/config-mirror.zsh:354-356`). At A2 M5's 12-28 ms per fork at load ~490, that is ~1.1-2.6 s per start [E: 31 slugs × 3 forks × 12-28 ms].
- Both forms remove this mutation work. Only the exclusion also removes the globs.

**Behaviour change is negligible** [M: `emulate -L zsh; setopt extendedglob` arrays over `~/.claude/projects`]:
- Across all temp slugs, only 6 files sit inside canonical `memory/` dirs. They belong to 4 slugs, all probes: `-private-tmp-memprobe*` and one `scratchpad-probe-proj`.
- The 6 quaternary temp real dirs that adopt would move are all empty.
- No unresolved `-var-folders-*` or `-tmp-*` slugs exist, so the two patterns cover the whole stock.
- The ~17.4k existing temp-slug memory symlinks per account stay where they are. They are harmless, and pruning them is an operator decision (A8-1 correction 1).

## 3. Changes to the README

1. **Wave 1.1 (README.md:158), replace the edit-points cell** with:
   > `lib/config-mirror.zsh:294-301`: add `setopt extendedglob` directly under `emulate -L zsh` (`emulate -L` makes it local). Write both globs as `"$cano"/^(-private-var-folders-*|-private-tmp*)(N/)` and `"$dst/projects"/^(-private-var-folders-*|-private-tmp*)(N/)`. A `case`/per-slug skip inside the loop is **not** acceptable: it still stats about 18k entries twice and builds the 18.9k-key hash, which keeps 50-86 % of the walk [M, gap-G1 §2] and 9.0 s of it at load ~520 [M, A2 M4]. Do not add an mtime or generation stamp (§6, S5).

2. **Wave 1.1 tests**, add to `tests/config-mirror-memory-adopt.bats`. The fixture has:
   - `canonical -private-tmp-x note.md` and `canonical -private-var-folders-ab-T-y note.md`, each with real canonical memory.
   - `strand .claude-secondary -private-tmp-z note.md`, a dst real dir with no canonical.
   - `canonical -Users-me-proj note.md`, a control slug.

   Assertions:
   - (a) No `memory` link exists under either temp slug in `.claude-secondary/projects`.
   - (b) `-private-tmp-z/memory` is still a real dir, and `~/.claude/projects/-private-tmp-z` does not exist (not adopted).
   - (c) The control slug is linked to canonical.
   - (d) **Form pin:** run `zsh -fxc "source '$MIRROR'; _cc_sync_memory_mirror \"\$HOME/.claude-secondary\"" 2>&1` and assert 0 lines match `slugs\[-private-`. A `case` skip would still trace a hash insert for every temp slug. (a)-(c) cannot tell the two forms apart, so (d) is what makes the test fail.
   - (e) A slug that merely *contains* `-private-tmp` (e.g. `-Users-me-private-tmp-notes`) is still linked.

   Run it under `/bin/bash` 3.2 and check the `1..N` plan line.

3. **Before landing**, change `a2-memmirror-scan.zsh:13,15` to the same `^(...)` pattern (and `setopt extendedglob`), then re-time quaternary and secondary. Pass condition: the walk is ≤1 s at load ≤~150. This session's inline replica gave 0.39-0.90 s [M]. That run does not replace the re-time on the committed script.

4. **#1 impact cell (README.md:31) and summary item 1 (README.md:14)**, restate as:
   - **Walk:** 1.7-7.3 s down to 0.3-0.9 s at load ~100-135 [M: A8 replica plus gap-G1 §2]. At load ~520 the drop is 13.8 s down to an estimated ~1.4 s [E: 13,830 ms × 10 %, the measured excl/full ratio].
   - **Mutation forks:** the pending link and adopt forks (31 + 6 on quaternary, 25 on secondary) are also removed [M].
   - **Dispatcher p50:** "7.4-9.2 s → ~3 s on isolated accounts" stays an **upper bound [E]** until the #14 ledger confirms it, because the walk replica explains only part of the +5.3 s same-hour gap (A8-precompute-load.md:522,531-534).
   - **Bound hits:** count them against the **~80 real kills [E, D2 README.md:81]**, not 107. That gives up to ~76 of ~80 kills per 2 d removed [E: 80 × 88/93 isolated share of ≥9 s runs, A8-precompute-load.md:521]. This is an upper bound: the non-walk parts of config-mirror-assert (mirror loop over 1,305 entries, reap, parity, drift and budget checks) and the other children still run.
   - **Shell launches:** each launch on an isolated account gets ~1.4-6.4 s faster at load ~130 [M: full − excl, paired, §2]. Remove "2-14 s".
   - **Under a `case` skip** at load ~500, config-mirror-assert still reaches the 9 s bound on most isolated starts [E from A2 M4], so #2's "killed" notices would keep firing there.

5. **README.md:229** stays as written. With items 1-2 it is now consistent with §5.

## 4. Recommendation (replaces #1 part 1)

| field | value |
|---|---|
| Change | Temp-slug **glob exclusion** in both globs of `_cc_sync_memory_mirror` plus a form-pinning bats test |
| Expected impact | Walk −85-91 % [M, §2]: −1.4-6.4 s per isolated start and launch at load ~130 [M]. Up to ~76 of ~80 real kills per 2 d [E, upper bound]. Pending-mutation forks go to 0 [M]. Drop paths closed: once config-mirror-assert finishes, the 3 safety checks after the walk (`config-mirror-assert.sh` checks after `:17`) run again on isolated starts. Tokens: 0 change |
| Effort | S (one function, one test file, one script filter) |
| Risk | Low. Temp slugs stop sharing memory, and only 4 probe slugs hold any memory file [M]. With `emulate -L zsh`, `extendedglob` stays function-local, so callers sourcing the lib from `~/.zshrc` are unaffected |
| settings.json edit | No |
| Conviction | 88 for the exclusion form. The `case` form should not ship. |
