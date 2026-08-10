# cluster C — land/ship/gate/deploy-live/postland-verify — triage vs origin/main @ 51bdb524

Measured 2026-08-09/10 against `origin/main` = `51bdb524` (fetched this session). Live layer =
shared checkout `~/Development/claude-infrastructure` @ `c2ccbeb8`, **19 behind trunk, 0 ahead,
`core.bare=false`, tree clean except 2 untracked files**. Verifier daemon `com.claude.postland-verify`
is **loaded and running** (pid 85038, mid-corpus at `61799d76237a`). No test suites were run.

## Summary

counts: **PRUNE 53 / UPDATE 13 / KEEP 36 / MERGE 18**  (= 120)

### The three measurements that govern this whole slice

**1. The 18 `tests/deploy-parity.bats` items are ONE root cause and it is DEAD.**
All 18 cited shas are ancestors of trunk, dated 2026-07-25 → 2026-07-28. Across all 124 postland
stamps, `tests/deploy-parity.bats` appears in the `failing` list exactly **18 times, and never once
after 2026-07-28T20:21Z** — 106 stamps have been written since with zero recurrence. In every one of
those 18 stamps it failed **alongside the identical 5-suite cohort** (`desk-arm-live`,
`desk-recycle-durable`, `lr-team-audit`, `session-continue`, `waiting-recycle`), which is the
`$HOME`-hermeticity cohort item `9a57611ececc` names — one cause, 18 ids, as the lead suspected. The
fix is `dee7031a` (2026-07-31, *"29 hermetic tests rode 2 live ones out of the land gate"*), followed
by `f84e48de`, `5b6c7e3e`, `ae63e3ff`, `7f6eccd9`. Today `deploy-live`'s own post-deploy host check
logs `ok tests/deploy-parity-live.bats`. **All 18 PRUNE, plus the 5 `deploy-parity-live` HOST RED
items (`525ec16e7124` `f271cd880295` `8028ce79f5b9` `dda10a298842` `27ac5a5b258f`) — 23 items retired
by one evidence chain.**

**2. The deploy-live bootstrap deadlock STILL HOLDS today — but every item states the wrong
mechanism.** Items say *"no GREEN tree is a descendant of live HEAD"* (the anti-rollback guard,
`deploy-live.sh:642`). That is **refuted**: last-green `71e96bcbc825` **is** an ancestor of live HEAD
`c2ccbeb8`. The live refusal, verbatim from `~/.claude/autonomy/postland/deploy.log`, is now:

> `deploy-live: REFUSED — no GREEN stamp among the newest 200 commits of origin/main — nothing is safe to deploy`

Cause: `SCAN_N=200` (`deploy-live.sh:76`), and last-green `71e96bcb` is **252 commits behind trunk**,
i.e. it has fallen out of the scan window. So the deadlock migrated from *anti-rollback* to
*green-starvation*, and it is now purely a function of green rate vs trunk velocity. Green rate all
time: **3 green / 124 stamps (2.4%)**; verdict census `106 red · 14 cut · 3 green · 1 hung`. Newest
green is **47.5 h** old (`POSTLAND_MAX_STAMP_AGE_H=24`, so the net attests `inert`).

**3. The verifier is NOT dead and NOT deadlocked — it is 33 commits behind and converging.** Lag of
the verified commit behind trunk, newest 12 stamps: 114 → 113 → 109 → 97 → 91 → 82 → 78 → 52 → 50 →
49 → 44 → 33. It catches up but never closes, because reds are small and churning (newest reds name
1–3 suites out of 369) and 5 of the newest 12 runs were **cuts** (no verdict at all). This is the
`(1-q)^n` problem, not a broken tree — corroborating `55c70e890f6b` and `8f50584fdfe1`.

Corollary that decides ~10 verdicts: the items minted `@ f60b7ca220ee` were filed 2026-08-09 18:00–19:02
from a run verifying a commit **247 behind trunk and 2 days old**. Every red the verifier files is
stale by construction at filing time.

## Verdicts

```
e34a0e48833e | PRUNE  | branch cc-001759-77337 does not exist (git branch -a: no match); .mcp.json still absent from origin/main — nothing can land it
3df911c0470e | UPDATE | deadlock real TODAY but mechanism migrated: last-green 71e96bcb IS an ancestor of live HEAD c2ccbeb8; refusal is now "no GREEN stamp among the newest 200 commits" (252 behind). --force is the wrong remedy for the new mechanism
9be5e66e1c34 | KEEP   | hooks/completion-assert.sh:299-303 on trunk: `session_writes_paths … rc 1 → _ca_assignee || return 2` verbatim; the fired-peer gap survives
cb6701bf2217 | KEEP   | scripts/launchd-path-lint.sh absent from origin/main; only tests/capacity-alarm-launchd-path.bats exists (still one-script-scoped)
735283f4fa69 | PRUNE  | `git config core.bare` = false on the shared checkout today; the ff-only misattribution premise is gone
c50158434c7a | KEEP   | scripts/deploy-now.sh:77 `git merge --ff-only origin/main` still on trunk, still ungated; the operator fork is unsettled
70dff02dcf4a | KEEP   | postland-verify.sh:350 corpus QoS still `nice -n 19 taskpolicy -c background`; only the PRELINT band moved to utility — the corpus decision is untaken
4e3de50ec183 | MERGE  | canonical 3df911c0470e — same deploy-live refusal, older mechanism text (29911f22 setup-token loader)
1e463de97b5d | PRUNE  | this item IS a disproof record, and it re-verifies today: `git diff origin/main -- hooks/completion-assert.sh` is empty on a clean tree. No work in it
6110fc45141e | KEEP   | bin/cc-dispatch has no behind-trunk guard (grep rev-list --count/behind/reset --hard: only prose, no predicate); worktrees handed out stale
07e6e3888e9c | UPDATE | HALF FIXED: the RED path now files with --condition (postland-verify.sh:2023, cond_slug at :647). AUTO-REVERT/HUNG paths still per-event — the residue is 617d99d7a0b4
7d6b462a468c | UPDATE | the deploy-circle half is stale (checkout is 19 behind not 17+; refusal reason changed). The handoff-rail half is unverified and stands
d5534a171556 | PRUNE  | its whole deliverable was `gate_admit` load-admission — DELETED by land-pipeline-v2 ("It is deleted, not tuned", ship-land.sh:545); owning item f8e40b4c577d is done (9478505449a2 content-verified it)
8b90c69e0edd | PRUNE  | KILLED vs HUNG are distinct terminal states now: a `"verdict":"hung"` stamp exists, classify_hang routes it, and flakes.jsonl records signal deaths as `outcome:"cut-not-red"`
a0718a5d78b3 | PRUNE  | landed and content-verified: tests/pkill-scope.bats + the pkill clause of scripts/test-hermeticity-lint.sh are on trunk; signal-death is a third state
e733ca203b07 | KEEP   | all 7 named worktrees still present today (wt-evalbin, wt-tmux-isid, gu13c-{mem,gate,m4m5,qos}, opus5-effort); 425 worktrees, 826 local branches
9478505449a2 | PRUNE  | a stale-precondition RECORD whose content I re-verified; its ask is 35de32d78364's operator decision, not separate work
35de32d78364 | UPDATE | the sweep's own FIRST deliverable never landed: `git log --all --diff-filter=A -- scripts/stranded-exposure.sh` is EMPTY. Figures are 14 days stale (36 branches then, 826 local refs / 425 worktrees now) — re-derive before acting
0fa7d7512a3c | PRUNE  | checkout is 0 ahead of origin/main today (`rev-list --left-right --count origin/main...HEAD` = 19 0); the stranded kitty commit is gone/landed
8b2de5bc0f3b | KEEP   | tests/kitty-recovery-launch.bats still greps 'com.googlecode.iterm2' (5 sites); newest churn f28c4278 is a ShellCheck-directive fix, not the spawn seams
9f69e13fc2e0 | KEEP   | runner.log still has ZERO 'resident unsanctioned' lines (2 'IDENTITY LEAK' from the old sweep); the guard's live path remains unproven
73b8c28f6aae | UPDATE | CONCURRENCY_PROGRAM.md §S6.4-MEASURED (2026-08-09) resolves BOTH premises oppositely: "17.95ms vs 2.20ms → 8.2×" does not reproduce; outcome was evidence+instruments, NO runtime change; hook-chain RE-OPENED. Rewrite the target or close
84f053be2850 | KEEP   | migrations/0007-mailbox-wake-arm-registration.sh on trunk; deploy.log shows it STAGED (c10, operator-owned) alongside 5 others — still unrun
63929c8d6072 | UPDATE | the ratchet exists and IS wired into ship-land (DEAD_LINT=scripts/bats-assert-liveness.py, ship-land.sh:1541-1552) and shellcheck runs on changed files. The "89 dead assertions across 28 files" count predates 548161cf (revived 23+1) — re-measure
5207d553dce2 | KEEP   | bin/cc-backlog claim still check-then-write (claimer_live oracle, no CAS/O_EXCL on the claim record); the same-second double-claim window is open
e281cde67a48 | KEEP   | no reset-at-claim in cc-dispatch; same surface as 6110fc45141e/74f624d1fb98 but distinct symptom (foreign staged files vs stale base)
8255aa85cb26 | PRUNE  | the shared checkout carries ZERO unlanded commits today (0 ahead); a6d5c5f2/e65d7adb are gone from HEAD
d4fcb1f5eb53 | UPDATE | tests/kitty-conf-bindings.bats still asserts 3 of the 4 named chords, but the suite churned 3× since (cca7cc98, f64220fb, 56c99348) — re-derive which assertions survive before dispatching
4169969836ac | PRUNE  | hooks/backup-before-write.sh is CLEAN today; hooks/lib/read-before-write-parity.sh is untracked, and deploy-live.sh:364 explicitly skips untracked ("untracked cannot block a --ff-only")
5ab388498ef3 | PRUNE  | all 8 named pids (33674 5037 20398 67253 73968 82819 91568 88701) are dead — kill -0 on every one
3847d83eef1a | MERGE  | canonical 3df911c0470e; break-step 26-deploy-gate-unblock is satisfied per 1572de03463c
e1a0d2e7937f | KEEP   | install.sh is still reachable ONLY on the merge path (deploy-live.sh:726); the file now DOCUMENTS this hazard at :286-307 and the reason it stays — the structural gap is unfixed
08d2f8651ccd | UPDATE | refusal count and reason both changed (now "no GREEN stamp in newest 200"); bin/cc-blockers has 102 'deploy' references, so the alarm may now exist — re-measure the SILENCE claim before treating it as a gap
16f0abd6e9bd | MERGE  | canonical 3df911c0470e — same refusal, sha 3725e543 superseded (last-green is now 71e96bcb)
3c4083af1397 | MERGE  | canonical 3df911c0470e; its stated cause (target BEHIND live HEAD ⇒ anti-rollback) is refuted — last-green IS an ancestor of live HEAD
456d5c61f4c8 | KEEP   | grep of origin/main:scripts/deploy-live.sh for prune|EXTRA|dangling|-type l returns ZERO — no prune leg anywhere; the EXTRA converse is still missing from deploy-parity-assert
e38d68f0c3c2 | UPDATE | the literal ceiling 8 is GONE (derived from hw.ncpu now, ship-land.sh:66) and the liveness ratchet IS wired via DEAD_LINT. The shed-means-nothing-runs shape survives; the "25 dead assertions" figure predates 548161cf
b59eb997d035 | PRUNE  | the ':22 real tree is CLEAN' case is gone from tests/test-hermeticity-lint.bats (setup now dogfoods rule 1), and runner.log 2026-08-09T23:48:35Z records the prelint clean whole-tree strict
c0ed177a12f7 | KEEP   | scripts/growth-coverage.conf has 85 non-comment rows and none for security / vendor / autonomy-postland / autonomy/recycle-events.jsonl
7c05d45796d8 | KEEP   | test-hermeticity-lint.sh now carries RULES 1-6, none of them CLAUDE_CONFIG_DIR: its 4 mentions are prose + exclusions (:265, :785, :792, :818). The seam is still unpoliced
c13dad7d5dbe | PRUNE  | BOTH prescribed fixes landed: install.sh skips a label "executing right now, not reloaded" (:700-703) and issues a CONDITIONAL `launchctl enable` only when the override db carries a disabled bit (:718-723)
1572de03463c | MERGE  | canonical 3df911c0470e — trunk is still not green, which is exactly this item's stated unblock condition
4f12ec722bad | MERGE  | canonical 3df911c0470e; its evidence is superseded (live HEAD moved, verifier converging 114→33 today)
a9e5b17d3420 | KEEP   | still no ENFORCING guard: deploy-parity-assert.sh:402-455 only SCORES provenance; scripts/deploy-now.sh:77 raw ff is untouched
525ec16e7124 | PRUNE  | tests/deploy-parity-live.bats reads `ok` in today's deploy.log post-deploy host checks; sha 3e423b762e60 is 4 days old and an ancestor
f271cd880295 | PRUNE  | same host-check evidence; 7ded71b83209 ancestor, 2026-08-05
8028ce79f5b9 | PRUNE  | same host-check evidence; d6394732c994 ancestor, 2026-08-02
dda10a298842 | PRUNE  | cited sha e7e2ea9445b3 is NOT an ancestor of origin/main (never landed) AND the suite is green in today's host checks
27ac5a5b258f | PRUNE  | same host-check evidence; e9cabc46698d ancestor, 2026-08-05
a31d1fe3de3d | MERGE  | canonical 50af9e4a4258 (the revert actuator cannot act); its sha 57e162494c10 is not even an ancestor of trunk
2f53940bd969 | MERGE  | canonical 50af9e4a4258 — byte-identical triplet with e0ef8d3baae6/11baa19409bc, minted by the per-EVENT key at postland-verify.sh:1873
e0ef8d3baae6 | MERGE  | canonical 50af9e4a4258 — same triplet
11baa19409bc | MERGE  | canonical 50af9e4a4258 — same triplet
02319b04b35f | MERGE  | canonical 50af9e4a4258; d25c4dd47384 is 729 commits behind trunk
50af9e4a4258 | KEEP   | AUTO-REVERT INERT, 3 of 3 attempts, none landed, last exit 90 — the veto arm genuinely cannot actuate and nothing on trunk fixes it
c8ab62671eab | KEEP   | no re-verify-at-current-trunk step exists in bin/cc-dispatch; and this slice measured the exact predicted cost (the f60b7ca2 cohort, 247 commits stale at filing)
56fba3527563 | PRUNE  | fixed by 707319a2 ("three test identity writes could re-author every worktree"); runner.log 2026-08-09T23:49:27Z records `git-identity-lint.sh clean (whole-tree strict)`
2cb1a174c5bd | PRUNE  | same class, same evidence — git-identity-lint is clean whole-tree on today's tree
bb78d6fca79f | PRUNE  | cited sha a1743ffebd35 is NOT an ancestor of origin/main, and tests/bats-assert-liveness.bats appears in no stamp since
02d413c9f382 | KEEP   | tests/boot-resume-launch.bats is the #1 recurring red — named in 18 stamps, incl. the 3 newest reds (2026-08-09 22:39 / 14:12 / 12:13). Canonical for this suite
99df8fdb4fda | KEEP   | tests/boundary-handoff.bats named in the 2 newest red stamps (2026-08-09 22:39, 14:12); live
a8651e2f385c | MERGE  | canonical cb6701bf2217 — this IS the launchd-PATH class (sysctl unreachable ⇒ SKIPPED); e6de2e15 is 524 behind and the suite is in no recent stamp
d4003e8288e3 | KEEP   | tests/cc-kitty-socket.bats named failing in the 2026-08-09T07:20Z red stamp; live
c6a031ebd588 | PRUNE  | d25c4dd47384 is 729 commits behind trunk and tests/cc-pane.bats appears in no stamp since; the ratchet it names is not currently failing
4c23468bdaea | PRUNE  | fixed on trunk 2026-08-09 by 670d93f2 ("a stale assertion demanded the one remedy…") — the suite's newest commit postdates the item
4b22325d29af | PRUNE  | deploy-parity cohort — see Summary §1 (last recurrence 2026-07-28; fixed by dee7031a)
7f987616606b | PRUNE  | deploy-parity cohort
92cb8d1483fa | PRUNE  | deploy-parity cohort
f0152b0cef9b | PRUNE  | deploy-parity cohort
b8cd08a7b7ed | PRUNE  | deploy-parity cohort
592fa4d06256 | PRUNE  | deploy-parity cohort
52774cd54d16 | PRUNE  | deploy-parity cohort
39f7d520f5ba | PRUNE  | deploy-parity cohort
0163a0d31517 | PRUNE  | deploy-parity cohort
8422cd51c9a4 | PRUNE  | deploy-parity cohort
99752779e916 | PRUNE  | deploy-parity cohort
e58a281f7b84 | PRUNE  | deploy-parity cohort
d5ead4c27b87 | PRUNE  | deploy-parity cohort (the id the other 16 were hand-blocked onto)
c21daa45eea5 | PRUNE  | deploy-parity cohort
5210fcc8c4c4 | PRUNE  | deploy-parity cohort
e3a48705cd6c | PRUNE  | deploy-parity cohort
9c16bc69f9b0 | PRUNE  | deploy-parity cohort
b187766fafbd | PRUNE  | deploy-parity cohort
d5a0cfc1686e | PRUNE  | 4b3b6b010e6c is 291 behind trunk; tests/fire-engagement.bats appears in no stamp since 2026-08-07
c3aeefe393f1 | PRUNE  | f60b7ca2 cohort — filed 2026-08-09 from a run verifying a commit 247 behind trunk; suite absent from every stamp after that run
1b7f0279c720 | PRUNE  | f60b7ca2 cohort — same
9b19d4392eb5 | PRUNE  | f60b7ca2 cohort — same
13a0befd7acd | PRUNE  | f60b7ca2 cohort — same
07603db55a30 | MERGE  | canonical 8b2de5bc0f3b — same suite (kitty-recovery-launch), and that item proves it reproduces on clean origin/main, which this one does not
b0b83b6c5845 | KEEP   | bin/cc-backlog cmd_dups (:1474) still groups on project+dodRef only; scan rows carry no dodRef, so the population stays invisible. Confirmed live: 23 sha-suffixed items in this slice alone
e1c603144edc | UPDATE | the INSTANCE dissolved (git-identity-lint is clean whole-tree today, 707319a2), but the bisect-degenerates-when-last-green-is-far-behind defect is untested and the blast radius (POSTLAND_AUTOREVERT on a wrong culprit) is unchanged — last-green is now 252 behind
33c286c30624 | KEEP   | 14 of 124 stamps are `cut` (11%), incl. 5 of the newest 12 — cuts are now the dominant non-verdict and the corpus gather is still the suspect
8f50584fdfe1 | KEEP   | re-measured today: 3 green / 124 stamps = 2.4% (item said 2.6%/115); newest green 47.5h old; reds still tiny and churning. Premise stronger than when filed
21032726df58 | PRUNE  | pid 82053 is dead (kill -0 fails); the verifier now running is pid 85038 from the live path
cc89fc8dc765 | KEEP   | no PRE_PLAN_GRACE_S on trunk (grep: 0 hits; tap_plan at :1037 parses the plan line but the stall clock is not gated on it). Now non-latent in effect: cuts are 11% of all stamps
d0945db40dcd | KEEP   | postland-verify.sh:2508 still seeds `pv@selftest.local` and :2661 still asserts it — the fixture still contradicts identity_snap_ok
9a34c9b9865a | KEEP   | selftest still reads shared $STATE/$LASTGREEN/$STAMPS with no private-dir override; the daemon is LIVE today (pid 85038), so the race is reachable right now
eea1070e386e | MERGE  | canonical d0945db40dcd — same file, same fixture-vs-guard contradiction, different assertion
617d99d7a0b4 | KEEP   | verified on trunk with corrected line numbers: THREE per-event add sites remain without --condition — :1758 (AUTO-REVERT INERT), :1873 (AUTO-REVERT outcome), :2074 (HUNG). Only :2023 (RED) is condition-keyed
62599dd76a60 | KEEP   | no TAP is preserved: the only bats.tap reference is :2098 inside $RUN_TMP, which release_lock rm -rf's. Zero `stamps/*.tap` on disk
847e4d2c4753 | KEEP   | zero `cc-backlog done|resolve|close` call sites on trunk (name-not-variable grep over $BACKLOG_BIN); only 4 `add` sites. No green-side retraction
01ab05685857 | UPDATE | "INERT" is wrong — the daemon is LOADED and RUNNING (launchctl: 85038; stamps advancing 114→33 behind today). The true fact is green STARVATION: newest green 47.5h old vs a 24h max
7e2e0ab9c358 | KEEP   | deploy-parity-assert.sh:438 still uses "an ungated path either names a REF or is not a merge at all" as the discriminator — the falsified rule is unchanged
e65d45027b3d | PRUNE  | premise consumed: 124 stamps have been written since, 3 of them green; the §7 embargo question is answered by the green-rate evidence, not by "the first post-repair stamp"
e91937f897cc | UPDATE | land-pipeline-v2 took the corpus OFF the land path (smoke ≤120s, IN_LAND_LOCK forbids heavy work in-lock), so the "~1400-test suite × N landers" premise is dead. But concurrent land-gate death SURVIVES: flakes.jsonl 2026-08-09T23:12-23:20 logs three `Terminated: 15` land-gate cuts at loadavg 16-20
fb178d6d8d14 | KEEP   | no subset assertion exists — grep of ship-land.sh for SUBSET/"subset of gate-select" returns nothing; the re-round still selects from an unattested range
9a57611ececc | UPDATE | the DISK TRUTH is refuted (124 stamps / 3 green, not 14 / 0) and the escalation premise is gone (postland_net_live v2 sets NET_STATE and NEVER blocks a land). The (c) conflation survives: `[[ "$newest" -gt 0 ]] || return 0` still cannot separate no-stamps from zero-greens. Also: the 7-suite cohort in its SECOND finding is dead since 2026-07-28
e097421ab166 | MERGE  | canonical 7c05d45796d8 — identical ask (a CLAUDE_CONFIG_DIR rule in test-hermeticity-lint), and the rule numbering it cites has since shifted (rules 1-6 exist, none is this)
af08d04ef450 | PRUNE  | RULE 6 (the INHERITED-VALUE seam, test-hermeticity-lint.sh:187-206) IS shape 5c, and it explicitly argues why it is a sixth rule rather than a third shape of rule 5
a03198ee0232 | PRUNE  | fixed: in_allowlist (:1243-1249) now three-states rc 0/1/>1 with a bounded retry, and the selftest at :2335-2338 positively controls it ("a killed check must never be a verdict")
423947ccdb96 | MERGE  | canonical 02d413c9f382 — same suite (boot-resume-launch), and that item carries the live recurrence evidence
e5bfe6d0af02 | PRUNE  | fixed: tests/handoff-fire-kitty.bats now documents and implements the CONDITIONAL drain — "drain only when the script is on STDIN, never on `-e`" — which is exactly this item's prescribed remedy shape
14531016f6a7 | KEEP   | suite's newest commit 5515ac08 (2026-08-08) PREDATES the item (2026-08-09); nothing on trunk addresses the env-conditioned 3-RED, and its own positive control is one of the failures
19ae324e9697 | KEEP   | load-sensitive-by-construction stall case unchanged on trunk; POSTLAND_STALL_S is still a constant and the 1-of-3 flake row stands
a622864e0ad0 | KEEP   | measured on trunk: `^not ok` survives 3× in ship-land.sh, 1× in deploy-live.sh, 1× in nightly-regression.sh, and TAP_NOTOK_RE appears in NONE of the three
55c70e890f6b | MERGE  | canonical 8f50584fdfe1 — same conclusion (contention, not a broken tree) with weaker numbers; the green-rate item carries the live measurement
e90959ed6f75 | PRUNE  | core.bare is false today; the ff-only death at deploy-live.sh:367 cannot occur from this cause
08bb6d205d63 | PRUNE  | the shared checkout is NOT diverged — 19 behind, 0 ahead, fast-forwardable; no destructive reset is needed
74f624d1fb98 | MERGE  | canonical 6110fc45141e — one surface (worktree handover hygiene at claim time); this is the foreign-staged-files face, 6110fc45141e is the stale-base face and names the fix that covers both
99b715f31a98 | KEEP   | scripts/wrap-ledger.sh computes LIVE_LAG/LIVE_BREACH from a commit-count budget only (:364, :397); no `--diff-filter=A` leg, so an added file is still invisible at lag≥1
```

## Master items

### M-landgate-1 — Make a GREEN stamp reachable at trunk velocity, so the live `~/.claude` layer converges

**Encompasses:** `3df911c0470e` `4e3de50ec183` `3847d83eef1a` `16f0abd6e9bd` `3c4083af1397`
`1572de03463c` `4f12ec722bad` `08d2f8651ccd` `01ab05685857` `8f50584fdfe1` `55c70e890f6b`
`33c286c30624` `cc89fc8dc765` `19ae324e9697` `a622864e0ad0` `62599dd76a60` `9a57611ececc`
`e91937f897cc` `fb178d6d8d14` `e1c603144edc` `50af9e4a4258` `a31d1fe3de3d` `2f53940bd969`
`e0ef8d3baae6` `11baa19409bc` `02319b04b35f` `02d413c9f382` `423947ccdb96` `99df8fdb4fda`
`d4003e8288e3` `14531016f6a7` `8b2de5bc0f3b` `07603db55a30` `d4fcb1f5eb53` `d0945db40dcd`
`eea1070e386e` `9a34c9b9865a` `9f69e13fc2e0` `e1a0d2e7937f` `456d5c61f4c8` `99b715f31a98`
`c50158434c7a` `a9e5b17d3420` `7e2e0ab9c358` `cb6701bf2217` `a8651e2f385c` `7c05d45796d8`
`e097421ab166` `e38d68f0c3c2` `63929c8d6072` `c0ed177a12f7` `70dff02dcf4a` `e733ca203b07`
`35de32d78364` `9478505449a2` `84f053be2850` `7d6b462a468c`

**Why this is one effort.** One number gates all of it: `deploy-live` will not advance the live layer
until a GREEN stamp exists within the newest 200 trunk commits, and the green rate is **2.4%**
(3/124). Everything above is either (a) something that makes a run non-green — a genuinely red suite,
a false red from a torn TAP line or a fabricated verdict, a CUT from a stall bound that mis-measures
the counting pass, a QoS band that stretches a run past its wall; (b) something that makes a green
un-actionable once obtained — the 200-commit scan window, `install.sh` reachable only on the merge
path, no prune leg for deleted files, `wrap-ledger`'s LIVE rung blind to added files; or (c) an
ungated path that pushes live HEAD *above* the newest green and re-opens the gap (raw ff via
`deploy-now.sh:77`, the laundered `GATED` provenance verdict). Fixing any subset without the others
leaves the layer stale, which is why this has survived ~15 separately-filed items for three weeks.

**Impact.** This IS the land rail's terminal segment. Today **252 commits are landed on trunk and not
running**, including every hook and script fix in this slice; six C10 migrations are staged behind it;
`postland-verify` is 33 commits behind and will never close the gap at 2.4%. Closing it retires
**57 items** in this cluster alone, converts the standing `🚀 landed-not-live` rung into `✅`, and
removes the single most-cited blocker in the whole backlog. It touches enforcing stores directly
(`~/.claude` symlinks, launchd plists, `settings.json` via the staged migrations).

**DoD.** `deploy-live` advances the live layer autonomously on its 600s tick: a GREEN stamp exists
inside the scan window, the live checkout is 0 behind `origin/main`, `deploy-parity-assert` reports
no MISSING and no EXTRA links, and the postland green rate over the trailing 20 stamps is ≥50%.
Landed on trunk and observed in the enforcing store, not merely committed.

**Falsifier.**
`n=$(git -C ~/Development/claude-infrastructure rev-list --count HEAD..origin/main); [ "$n" -eq 0 ] && bash ~/Development/claude-infrastructure/scripts/deploy-live.sh --dry-run`

**First move.** Read `~/.claude/autonomy/postland/deploy.log | tail -40` and the newest 20 stamps,
then re-derive the two numbers this effort turns on: green rate over the trailing 20, and
`git rev-list --count <last-green>..origin/main` vs `SCAN_N`. Do NOT open with `--force`: the
mechanism every blocked item names (anti-rollback) is refuted, and forcing past the *current*
mechanism deploys an unverified tree.

**Order.**
1. **Stop manufacturing false non-greens** (cheapest, highest yield, no trunk change needed to
   validate): `a622864e0ad0` (one TAP grammar across ship-land/deploy-live/nightly-regression),
   `cc89fc8dc765` + `33c286c30624` (pre-plan grace so the counting pass cannot cut a healthy run —
   cuts are 11% of all stamps), `62599dd76a60` (preserve the TAP next to the stamp; every step below
   is archaeology without it), `19ae324e9697`.
2. **Fix the suites that are actually red now**, in recurrence order from the stamps:
   `02d413c9f382`/`423947ccdb96` (boot-resume-launch — 18 stamps, all 3 newest reds), `99df8fdb4fda`,
   `d4003e8288e3`, `14531016f6a7`, `8b2de5bc0f3b`/`07603db55a30`, `d4fcb1f5eb53`.
3. **Restore the verifier's own instruments**: `d0945db40dcd`/`eea1070e386e`/`9a34c9b9865a`
   (`--selftest` is red on trunk, so the tool that certifies the gate is itself uncertified),
   `9f69e13fc2e0`.
4. **Make a green actionable**: `e1a0d2e7937f` (install.sh off the merge path), `456d5c61f4c8`
   (prune leg), `99b715f31a98` (added-file lag), then re-check `08d2f8651ccd`/`01ab05685857` alarms.
5. **Close the ungated paths that re-open the gap**: `c50158434c7a`, `a9e5b17d3420`, `7e2e0ab9c358`.
6. **Reduce q structurally**: `7c05d45796d8`/`e097421ab166` (CLAUDE_CONFIG_DIR rule),
   `cb6701bf2217`/`a8651e2f385c` (launchd-PATH lint), `e38d68f0c3c2`, `63929c8d6072`, `70dff02dcf4a`
   (the QoS decision — operator fork), `c0ed177a12f7`.
7. **Judgment/operator items last**, once the lane moves: `35de32d78364`+`9478505449a2` (re-derive
   the numbers first — they are 14 days old), `e733ca203b07`, `84f053be2850`, `7d6b462a468c`.

---

### M-landgate-2 — Stop the post-land verifier from minting, and dispatch from consuming, work that is already dead

**Encompasses:** `07e6e3888e9c` `617d99d7a0b4` `847e4d2c4753` `b0b83b6c5845` `c8ab62671eab`
`6110fc45141e` `74f624d1fb98` `e281cde67a48` `5207d553dce2` `9be5e66e1c34`

**Why this is one effort (and why it is NOT part of M-1).** M-1 is about the *verdict*; this is about
the *record*. These ten share one loop with four broken joints, and every joint is on the path from
"the verifier observed something" to "a worker burned an hour on it": **(1) MINT** — three of four
`cc-backlog add` sites are still per-EVENT (`postland-verify.sh:1758/:1873/:2074`), so one condition
mints N items; **(2) DETECT** — `cc-backlog dups` groups on `dodRef`, which scan rows do not carry, so
the one population guaranteed to duplicate is the one the deduper cannot see; **(3) RETRACT** — there
are ZERO `done|resolve|close` call sites, so a condition-keyed item outlives its own fix forever;
**(4) CONSUME** — `cc-dispatch` hands out worktrees with no freshness or cleanliness assertion, and
`cc-backlog claim` is non-atomic in a same-second window, so two live workers can hold one item.
`9be5e66e1c34` belongs here because it is the same law one layer up: a fired peer that correctly
writes nothing is convicted by `completion-assert` for a sibling's dirt — the *worker* side of "a
check that cannot answer must abstain".

This effort is separable from M-1 by test: fixing every red suite in M-1 changes none of these four
joints, and fixing all four leaves the green rate untouched.

**Impact, from this slice's own measurements.** 23 of my 120 items (19%) are pure mint-side
duplicates — the 18 `deploy-parity` rows plus the AUTO-REVERT triplet plus siblings — and they cost
real dispatches: `4b22325d29af` burned a second peer on a defect already blocked as `d5ead4c27b87`;
`2b2aa30ffbf9` burned 3 dispatch attempts and 9639s idle on a condition that died six days earlier;
`6110fc45141e` measured a worker handed a tree **735 commits behind trunk** whose correct-looking diff
would have REVERTED trunk. That last one is the worst available outcome on the land rail and it
arrives wearing a correct diagnosis and a green local gate. Repo-wide the shape covers 57 open rows.

**DoD.** A recurring post-land condition maps to exactly ONE backlog item regardless of how many runs
observe it; a green run retracts the condition-keyed items for the suites it proved; `dups` can group
`dodRef`-less rows; `cc-dispatch` asserts a fresh, clean worktree before handover and re-verifies the
cited artifact against `origin/main` before work starts; two workers cannot hold one item.

**Falsifier.**
`cc-backlog list --all --json | jq -e '[.[] | select(.source=="postland-verify" and .status!="done" and (.title|test("@ [0-9a-f]{12}$")))] | length == 0'`

**First move.** `git show origin/main:scripts/postland-verify.sh | sed -n '1750,1760p;1868,1878p;2070,2080p'`
— the three per-event `add` sites — and convert them to `--condition` using the existing `cond_slug`
helper at `:647`, which the RED path at `:2023` already proves works. That is the smallest change that
stops the population growing while the rest is designed.

**Order.**
1. `617d99d7a0b4` → `07e6e3888e9c` — close the mint side (three add sites; the id-vs-condition
   design fork `07e6e3888e9c` names is already settled by the landed RED path, so it becomes execution).
2. `b0b83b6c5845` — give `dups` a second grouping key (normalised title with `@ <sha>` stripped), so
   the existing 57-row population becomes visible and retirable.
3. `847e4d2c4753` — green-side retraction. Settle its stated design fork first (which items may a
   green retract; what happens to a suite that is green because it was deleted).
4. `c8ab62671eab` — re-verify the cited RED at current trunk before dispatch. Depends on 1–3 being
   in place, or it just re-checks duplicates.
5. `6110fc45141e` + `74f624d1fb98` + `e281cde67a48` — one worktree-handover assertion covering all
   three faces (stale base, foreign staged files, polluted index): provision fresh, or reset to
   `origin/main` at claim time.
6. `5207d553dce2` — atomic claim. Reproduce the same-second race before believing any fix (the item
   is explicit that the cause is undiagnosed).
7. `9be5e66e1c34` — validate the fired peer's transcript (not the session), per the item's own
   reasoning; do NOT widen to "any write-free session", and note the `cc-fired` stamp is missing on
   9 of 16 live dispatched panes (`c163f42390a3`), so it cannot be the proof-of-fire.

## Notes for the lead

- **The single biggest cross-cluster fact:** `deploy-live`'s refusal reason CHANGED, and every item
  in every cluster that quotes *"no GREEN tree is a descendant of live HEAD"* or *"target is not a
  descendant"* is now stating a refuted mechanism. The live reason is
  **"no GREEN stamp among the newest 200 commits of origin/main"** (`SCAN_N=200`,
  `deploy-live.sh:76`; last-green `71e96bcb` is 252 behind). Anyone triaging a deploy-lag item in
  another slice should re-read `deploy.log` rather than the item. **`--force` is now the wrong
  remedy** — the fail-closed gate it would bypass is no longer the one that is firing.
- **Do not act on `3df911c0470e`'s `--force` run command, or on `4169969836ac`/`e90959ed6f75`/
  `735283f4fa69`/`08bb6d205d63`'s stash/unset/reset commands.** All four premises are refuted on
  today's checkout (`core.bare=false`, 19 behind / 0 ahead, clean but for 2 untracked files that
  `deploy-live.sh:364` explicitly ignores). Running the reset one would be destructive for no reason.
- **`hooks/lib/read-before-write-parity.sh` is untracked in the shared checkout** and appears in this
  session's own `git status`. It is nobody's loose end in this slice, but somebody's uncommitted work
  has been sitting there since at least 2026-08-05 — worth one line to whoever owns it.
- **Cross-cluster duplicates I spotted:** `9be5e66e1c34` (completion-assert exoneration) probably
  belongs to whichever slice owns hooks/session-attribution — I kept it in M-2 because its failure
  mode is worker-side, but if another cluster has the `completion-assert` family, move it.
  `73b8c28f6aae` (Wave B) is a `CONCURRENCY_PROGRAM.md` item, not a land-rail item — it landed in my
  slice by keyword only; hand it to whoever holds the concurrency program, with the note that
  §S6.4-MEASURED already resolved both of its premises oppositely.
- **Landmine for whoever picks up M-1 step 2:** `19ae324e9697` and `d0945db40dcd` both warn that
  `tests/postland-verify.bats` is convicted in 4 of the last 6 stamps — verify that suite's own state
  BEFORE editing the script it covers, or you will be debugging your own harness.
- **Verifier lag is the hidden staleness clock.** Because `postland-verify` runs 33–250 commits
  behind trunk, *every* item it files is stale at birth. When merging clusters, treat a
  `source=postland-verify` item's `@ <sha>` as a lower bound on its age, not as its filing date —
  the f60b7ca2 cohort in this slice was filed on 2026-08-09 about a 2026-08-07 commit.
