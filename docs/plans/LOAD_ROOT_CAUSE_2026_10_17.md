---
status: in-progress
---

# Load root cause 2026-10-17: implementation program

Scope (frozen): implement the agent-drivable fixes of `docs/research/load-root-cause-2026-10-17/DESIGN.md`
§5 (waves 1-5) so the same session work costs the machine less, with no throttling, demotion, capping, kill
policy or session reduction; make worktree lifecycle event-driven and reversible (PARK before any removal,
a tombstone before every removal, restore on resume); hand every operator-only step over as one script.

Design, evidence and per-row verify recipes: `docs/research/load-root-cause-2026-10-17/DESIGN.md` (§2 ranked
fixes X1-X27, §3 worktree lifecycle, §4 instrument, §5 WP table with file ownership). Axis evidence: the
`A-…J-*.md` files beside it. This plan does not restate them; a wave session reads its WPs' rows there.

## Phase 0 — Agent Team Orchestration

- **Execution locus per wave:** every wave is **S** (one dispatched `handoff-fire.sh` session per wave, each
  leading its own Agent Team, one teammate per WP, disjoint files per DESIGN §5). No T or L waves.
- **Concurrency:** W1-CI, W1-ACS, W2 and W4 are file-disjoint and fire together. W3 waits for W1-CI and W2
  (WP-15/16/17 depend on WP-7/8/9/10/13). W6 is conditional on the post-wave re-measurement.
- **Load etiquette for every session and teammate:** run only the bats/pytest files your WP names, never a
  full suite outside the land gate; no `ps -A` in new code; never kill or signal anything; never point
  worktree-gc, `git worktree remove/prune` or `git branch -d/-D` at a real worktree (WORKTREE_MANAGEMENT_V2
  HAZARD RULE) — use a throwaway repo.
- **Owned elsewhere:** live Wave 4c of `LOAD_AND_PROMPT_HOOK_TIMEOUTS.md` owns `scripts/wrap-ledger.sh`,
  `hooks/operator-readout.sh` and the session-continue / completion-assert / boundary-handoff Stop hooks.
  No WP here touches them, nor `hooks/lead-crash-watchdog.sh`.
- **Lead context budget:** the origin lead keeps ≥50% free; it fires, collects notify-back pings, reviews
  landed state and files operator steps. Succession point: after W1-CI, W1-ACS, W2 and W4 report, or at
  60% fill, whichever is first; recycle with this plan as the bridge.

## Waves

| Wave | Repo | WPs (DESIGN §5) | Fixes | Status |
|---|---|---|---|---|
| W0 | — | OP-1, OP-2, OP-2b, OP-2c | X1 fseventsd restart, X24 cleanups, wired + fs_usage capture | X1 **done by another actor** (fseventsd pid 96656, 14 MB at 2026-10-17 ~10:00Z; was 12-13 GB). Spotlight Privacy entry, OP-2* pending → operator script |
| W1-CI | claude-infrastructure | WP-1, WP-5, WP-6, WP-7, WP-8 | X2, X3 (bats), X8, X5, X4 | **landed 2026-10-17**: WP-6 adfb09b6c · WP-5 542d44d8b, 8bb8430fd · WP-1 250ff0a72 · WP-7 9d6cbcc5c, b9bc84e1a · WP-8 (ms365, staged) 13077919e..54c3943ad, migration renumbered 0067 (W4 took 0066). Operator: 0057 root re-install (backlog f433e92713c8), 0067 ms365 cutover (62694f2b1ffb) |
| W1-ACS | agent-context-sync | WP-2, WP-3, WP-4, WP-22, WP-30 | X3, X11, X20, X10, X26 | **landed** — agent-context-sync `5b1f10f1` (7 commits: WP-30 e72a536d, WP-4 a278cb90 + 38ddea63, WP-3 5d363837, WP-2 68eab10c, WP-22 b63251c9 + 5b1f10f1), content-verified; land gate `scripts/gate.sh` green (201 + 4441 passed), CI ci + diagrams green. Operator: OP-3 native pandoc install (backlog 2c1acaa94c3b), OP-6 point lane fires at `docs/lanes/COMMON.md` (dfc2d3f79629) |
| W2 | claude-infrastructure | WP-9, WP-10, WP-11, WP-12, WP-13, WP-14 | X6, X7, PARK tier, §4.2 detectors | **landed** — 55d01fcd4, bfab48403, 47970f271 + the WP-10 phase B land (PARK tiers, `--path`, late DETACH, ARCHIVE, all behind `--park-first`; AC-6 always on), content-verified; contract `docs/research/load-root-cause-2026-10-17/W2-CONTRACT.md`. Activation (`--park-first` in the nightly / wake run) is W3 |
| W3 | claude-infrastructure | WP-15, WP-16, WP-17 | X9 event queue, activation (staged), X17 | blocked on W1-CI + W2 |
| W4 | claude-infrastructure | WP-18-21, WP-23, WP-24, WP-25, WP-26, WP-28 | X12, X13, X25, X16, X15, X14 gate, X20, X18 | **landed** (`ba73b672e` WP-18/20/21/23/24/25/26; WP-19 + WP-28 in the follow-up land). WP-28 migration 0066 is c10: the operator applies it (`bash migrations/0066-hook-if-filters.sh --confirm settings.json`, which probes `if` on the live binary first). WP-25 adoption stays at a planned reboot |
| W5 | hammerspoon-config, reso | WP-27, WP-31 | X22, X6 for reso's janitor | owner repos; fire with W4's session if their CLAUDE.md permits |
| W6 | — | WP-29, WP-32, OP-4 | X-POOL, X27, X23 | conditional on the post-W1 re-measurement and operator rulings |

## Learnings

- The load (365-520) was ~65-85% four concurrent agent-context-sync gates, multiplied by per-test waste
  (xcrun cache misses per fresh test HOME, duplicated and sentinel-killed suites, polling forks) and by a
  wedged fseventsd (4th episode). Claude sessions themselves were 9-13%. DESIGN §1.
- A shared gate pool is **not** supported by today's numbers (X-POOL: back-to-back is 21% slower); remove
  the waste first, then re-measure.
- W2 (2026-10-17): teammate permission asks route to the LEAD's pane and freeze the teammate, and while
  one waits no team mail reaches the lead (three finished reports sat undelivered ~1 h). Triggers were
  content, not shape: multi-line `git commit -m` naming destructive verbs, and `rm -r`. Every brief now
  commits with `git commit -F <file written by the Write tool>`, bans `rm -r` (`mv d d.gone` instead) and
  `cd … &&` chains. The live pre-W2 teammate-auto-shutdown also removed each idle teammate's clean
  worktree (work survived on branches) — the defect W2 itself fixes.
- W2: `wt_pinned`'s `owner` pin (reflog < 60 min) pins every fresh tree, so a self-owned teardown
  (teammate-auto-shutdown, a failed fire) passes `--self-owned`; janitors keep the pin. Git cannot hold
  `refs/wt-tombstone/<id>` beside `/<id>/wip`, so every tombstone ref is one level down (`/<id>/head`).
- W2 resume state (2026-10-17 ~14:00Z, for a successor): branch `load-w2-worktree-lifecycle` holds 2
  unlanded commits (plan update; 2933e9631 slug fix + teammate clone mode — suites wt-tombstone, wt-park,
  teammate-auto-shutdown, cc-resume-resolve still to re-run, deferred by cc-bats). WP-10 phase B is on
  teammate w2-gcpark, branch `w2-gcpark` off origin/main bfab48403 (spec = its brief: `--park-first`
  opt-in, PARK arms i/ii, late DETACH, ARCHIVE behind CC_WTGC_ARCHIVE_FLOOR_GB, `--path`, pop split,
  AC-6). Finish: cherry-pick its commits, run tests/worktree-gc.bats + the four above, /ship, ping
  origin wt-cc-233108-87354-242 with DONE, self-close. Operator step filed: 678ee1ea5f12 (3 orphaned
  teammate pids).
- W4 (2026-10-17): every trim was proven byte-identical by replaying the W4 base hook from git (`tests/*-forks.bats`). Exec cuts: qos-rewrite 17→6, sentinel tick 23→6, statusline 9→5, cc-await-ping idle poll 8→2 plus a kqueue wait (mail wakes in ~0.1 s, steady state 16→3 per 30 s). Two traps cost an hour each: a named teammate's chat text never reaches the lead (checkpoints must go via SendMessage), and teammates stall on unanswerable prompts (`sed -i`, `rm -rf`, a hung bats reading stdin). Auto mode refuses an agent-run headless claude with scratch settings, so the `if` probe moved into the operator's apply. A test that replays a slow old arm must time the parity run, not repeat it (log-bash's 240 KB case cost ~70 s of CPU per gate).
- W1-CI: the fork-rate ceiling was 1,567/s in DESIGN X5 but the new 5 s sampler measured 2,000-3,400/s
  sustained (0.6% from a pid-delta probe), so `MAX_FORKS_S` is 3,400 and a window over ~29 s reads
  aliased. The design's negative-delta wrap rule never passes on a 5 s tick; a fall-back of more than
  half the pid space now counts as a wrap. `footprint -p` falls back to a NAME match for a pid it cannot
  read, so the watchdog uses `--pid` and requires the header to name that pid. The ms365 tools/list gate
  passed live (188 tools, direct == proxy); `parse-teams-url` is the one Graph-free tool with no
  `account` and is exempted by name. mcp-proxy 6.7.20 has no Host check: the 127.0.0.1 bind plus the key
  is the DNS-rebinding guard.
- W1-ACS (2026-10-17): measured — native pandoc output byte-identical to the wheel's on 175/175 corpus conversions (`--version` 0.040 s vs 0.077 s); with_progress sleep forks 26→2 per 5 s wait and 148→8 per 31 s, orphan sleeps per with_timeout/ticker stop 1→0, output byte-identical; collection union 4649 = 201 + 4448. Found in passing: install.sh's `ticker()` leaked its sleep too (fixed in WP-4), and pytest's `--deselect` matches by prefix, so the gate journal resumes through an exact-nodeid file (`GATE_DESELECT`) instead. The capacity gate refused 3 of 5 spawns at first ("8 sessions mid-turn"); those WPs went later, unforced. A fired session's `rm -r` sat ~1 h at a hook prompt, so use fresh scratch dirs instead.
