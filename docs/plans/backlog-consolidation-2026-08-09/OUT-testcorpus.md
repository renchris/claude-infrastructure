# cluster-C testcorpus — triage vs origin/main @ 51bdb524720aeb6c2fd49d14c1c584dce1456650 (2026-08-09 16:51 -0700)

Measured read-only: `git show origin/main:<path>`, `git log`, `git show --stat`, `wc -c`. No suite was run.

## Summary

counts: PRUNE 7 / UPDATE 11 / KEEP 20 / MERGE 2   (= 40)

**Headline for the lead — the open claim "trunk full-suite RED for 47h+, swings 3..14, mostly flakes" is
now WRONG in both halves.** Between 2026-08-09 00:06 and 02:31 PDT five commits landed that each cleared
one *named, reproducible* trunk red — `3dcac1f3` (pipefail, 22 sites), `d10bcd37` (permission-gate-lint
harness), `911ccc8e` (runner-stdin-immunity dead anchor), `3cb4fd28` (typed-send-lint fixtures read as 9
osascript sites), `c2ccbeb8` (tsv-field-collapse, the last offender). Four of my 40 items died to those
commits alone. The count swings not because the reds are flakes but because **the population is a mix of
three disjoint classes**: (a) deterministic harness defects, being retired one per commit; (b) genuinely
load-dependent wall-clock assertions (a measured class of 19 suites); (c) suites whose anchor into the
subject died when the subject was deliberately improved. Only (b) is a flake, and it is the minority.

## Verdicts

```
f46261b23ec2 | KEEP   | bin/cc-backlog `unblock` only rewrites status (:681, :2323); no evidence re-read anywhere on that path. Corroborated hard by this slice: 7 PRUNE + 11 UPDATE = 45% of items carry facts already dead, several re-touched days after their cure landed.
971995a07b05 | PRUNE  | Fixed by 3cb4fd28 (2026-08-09 01:18 PDT): `mk` now expands @OSA@ on the way to disk; osa-bounds AC22 21ok/1notok -> 22ok/0. Duplicate of c6f8553e16d5, which that commit names by id.
5ef317c7aa37 | KEEP   | agent-teams-enforce.sh still registered on the `Agent` matcher only (settings-templates/settings.example.json:155); no PreToolUse hook keys on context fill; the stated blocker (no per-phase dispatch record) is unchanged. NOT test-corpus — see Notes.
fe21305312ec | PRUNE  | BOTH cures landed: tests/cc-inbox-guard.bats setup() now installs a default CC_INBOX_GUARD_IT2 stub (:31-33), and bin/cc-inbox-guard bounds every it2 fork via _ig_bounded (:113-119, call site :180). The wrapper-side bound (5a80a64) the item's own `needs` note demanded is also on trunk.
0488b0e1e423 | KEEP   | ~/.claude/oauth-tokens still empty (dir mtime Aug 2, 0 entries). Real-TTY operator-only mint; premise verified unchanged.
087db20c3a24 | KEEP   | tests/cc-await-ping.bats:479-489 is byte-for-byte what the item describes — bare `sleep 2`, `grep -q 'verdict=killed'`, `[ "$rc" -eq 129 ]`. No commit touched the suite after the diagnosis. Both refuted hypotheses stay refuted; the prefix-bisect next step is unspent.
170a3b38f8c9 | UPDATE | Step (3) LANDED: lib/config-mirror.zsh:200/205 exports CLAUDE_CODE_OAUTH_TOKEN per launch and unsets it otherwise — exactly the set-or-unset requirement. Remaining = step (1) mint (that is 0488b0e1e423) + the four untested scope gates. Rewrite the item as "test the 4 gates on a minted canary", not "build the loader".
1a5f81c68100 | UPDATE | Premise TRUE, line numbers STALE: the two `application "iTerm2"` fixtures moved to scripts/typed-send-lint.sh:456 and :492 (3cb4fd28 inserted 15 comment lines). tests/iterm2-appname-lint.bats:51-52 still excludes only its own basename. Fix shape (pinned detector-file exclusion) unchanged.
043c2e5fcc7e | MERGE  | -> 7174eb206d25. Premise refuted: the suite is 12 tests, not 11, and both cited assertions now match the shipped chords (kitty-conf-bindings.bats:93/:105 assert the `${HOME}/.claude/bin/kitty-split-cwd.sh` form landed in 5b56f014; cca7cc98 finished the ⌘W half). What survives is exactly 7174eb206d25's ask: re-judge what the green suite still guards, do not close on green.
7174eb206d25 | KEEP   | Verified live and now stronger: this slice found two more items (043c2e5fcc7e, da4b516dc78a) whose symptom vanished while the underlying question did not. The re-judgment discipline it asks for has no mechanism yet.
e677db9bb7c1 | UPDATE | Half LANDED and it is the load-bearing half: bin/cc-pane-runner:150 now does `unset CC_PANE_CMD CC_PANE_CMD_INTERACTIVE` after reading the mode — the proven duplicate-session exposure is closed at the consumer. STILL LIVE: bin/it2-kitty:638 gates pre-delivery on non-emptiness (`[ -n "${CC_PANE_CMD:-}" ] && [ "$ARGV_SPAWN" = 1 ]`), not on a paired opt-in, and the suite arm was never written.
07ac6d58d88d | KEEP   | scripts/typed-send-lint.sh:125-138 still carries `bin/cc-pane::drv_iterm2_send` in the grandfather list with the "deciding that contract belongs to cc-pane's author" note verbatim; bin/cc-pane:159 drv_iterm2_send unchanged, still reachable from the `send` verb at :223.
329dd6350eb3 | UPDATE | The blocked-on premise moved: ca7db1a1 (08-09 16:21) landed `--cloud now creates and declares` and 4855c273/61799d76 report the create exists and the round trip stops at NOT-STARTED. The 1-of-4 intermittency figure predates that path and must be re-measured against it before it can block anything. NOT test-corpus — see Notes.
26d4010f1b22 | KEEP   | tests/teammate-auto-shutdown.bats:381 `wait_gone()` is unchanged — still `[ "$i" -lt 60 ]` × `sleep 0.05` = a 3s bound on an async `git worktree remove`. The census the item asks for, run here: 19 .bats files match `lt [0-9]+.*sleep|sleep 0\.[0-9]` — a class, not an instance.
5d0cfc272c4b | KEEP   | bin/cc-dispatch warm_worktree still `git -C <repo> worktree add "$wt" "$br"` (:682/:684) keyed on the item id, with no `status --porcelain` emptiness check and no `rev-list --count HEAD..origin/main` freshness check anywhere in the file. The closed loop is intact — and 8 items in this slice carry the "persistent thrash / rebase-exit-5" needs-note it explains.
a40afaee8d9c | MERGE  | -> 26d4010f1b22. Same file, same class, same fix: case 16's bare `sleep 0.5` survives at tests/teammate-auto-shutdown.bats:415. Merging keeps the census (19 suites) as one sweep instead of two per-case patches.
ad4743f9ee2c | KEEP   | scripts/gate-select.sh:442 is unchanged — `if gone and is_prose(gone) and (code == "D" or is_prose(path))`. is_document (:169) exists and is used by the A/M/T rung (:188, :540) but never by the delete rung. The latent gap the item found in the same read is also still there: INSTALL_RE (:111-113) covers hooks/, commands/, scripts/, skills/, bin/cc-*, launchd/ — agents/ is absent while install.sh globs it.
6783af2685ba | PRUNE  | Fixed by 707319a2 (2026-08-08 17:17 PDT, "three test identity writes could re-author every worktree on the box"). tests/deploy-link-parity.bats now writes identity through `git -C "${CC_LINKPARITY_REPO:?repo path required}"` at :307/:308, :331/:332, :349/:350 — the exact remedy the lint named, no allowlist. Commit reports git-identity-lint clean, 565 files, 0 escaping writes.
f660a37851cd | KEEP   | scripts/handoff-fire.sh:2046 verify_engagement unchanged: `local timeout="${FIRE_ENGAGE_TIMEOUT:-120}" … interval=3`, and both loops still advance with `t=$((t + interval))` (:2058, :2090) with no accounting for the engagement_seen scan they just paid for. engagement_seen's own header (:279) still calls itself "THE DETECTOR IS THE LATENCY".
130814a95132 | UPDATE | Core defect LIVE at the moved lines — scripts/cloud-ceiling-probe.sh:187/:189 still `printf '%s' "$out" | grep -qE …` with the status consumed. Two facts changed: (1) the TSV blocker it says to fix together is GONE — c2ccbeb8 discharged cloud-ceiling-probe with a reviewed exemption; (2) the class sweep 3dcac1f3 (22 sites) did NOT touch this file, and its triage rule ("a single-write producer under 64 KiB is safe") is precisely why it was skipped — this item is the measured counter-example, since $out is a 180s PTY capture that exceeds 64 KiB. Land it as a named exception to that triage rule.
dd76e48db6b2 | KEEP   | Verified by absence: `CC_FIRE_HEADROOM_GATE` appears ZERO times in scripts/test-hermeticity-lint.sh (18 hits for CC_FIRE_CAPACITY_GATE, incl. the ratchet at :961-989 and the selftests at :2354-2368). Rule 2 still enforces one of exit 9's two terms.
7c266e16fc94 | UPDATE | Premise holds and the number moved the wrong way: MEMORY.md is now 26,382 B (item says 25.9 KB / 25,917 B) — it grew ~465 B in the interval, and the loader is truncating today (this session's own load carried the over-limit warning). Restate the target against 26,382 B.
f6b460816387 | KEEP   | scripts/pane-id-lint.sh has no diff-scoping of any kind — zero matches for `git diff`, `--diff`, `exclude`, or a docs/research carve-out. Whole-tree, so every author still answers for every other's prose.
c6a47d8c3ccb | KEEP   | scripts/pane-spawn-coverage-lint.sh:151 pulls `-name '*.py'` into the scan and the file contains no `"""` handling at all; its own selftest (:177) exercises a python call-shaped line as GREEN, which is the blind spot, not a cure.
bacdfc4f63ab | KEEP   | scripts/payload-lint.sh F3 still re-implements the check as a regex anchored on the cc-notify argument position (:54-59) — zero occurrences of `--resolve` in the file. A lint-green payload can still name a target cc-notify cannot resolve.
3709b1649792 | KEEP   | scripts/permission-gate-lint.sh unchanged and the asymmetry is visible in four consecutive lines: the if/while/until/for rung skips depth++ on a one-liner (`if (s ~ /(^|;|[[:space:]])(fi|done)[[:space:]]*$/) continue`), the `case` rung one line below does `depth++` unconditionally with no trailing-esac test. d10bcd37 fixed a DIFFERENT defect in this suite (an unstubbed gate_red) and did not touch the lint.
cb9980e4b0e5 | KEEP   | Could not be refuted read-only: this is a post-DEPLOY host red against the live ~/.claude layer, and tests/test-hermeticity-lint.bats' second case is "--selftest is GREEN and every discriminating case is exercised" (:90) — a verdict about the deployed copy, which no git read reproduces. Per the contract, unread premise = KEEP. Note two rule landings since (643d2495 rule 1, 5f772838 rule 6) make a re-measure cheap and likely decisive.
4a74657d6088 | KEEP   | Test 12 is unchanged at tests/scratchpad-reaper.bats:165-172, and the fixture it names EXISTS on trunk with the right content (launchd/staged/com.claude.scratchpad-reaper.plist, `RunAtLoad <false/>`). So the red is neither the plist's value nor a missing file — which sharpens the item's own "establish whether it is the plist, the fixture, or live state" to: it is the harness (plutil invocation / $REPO resolution / staged-vs-live path), the same class as 911ccc8e and d10bcd37.
b3c4e8d9e041 | PRUNE  | Fixed: tests/session-continue.bats now pins HOME (:17) AND exports the seams the hook actually reads — CONTINUE_IDL (:39) and CONTINUE_LOG (:40) — with a comment recording the writer/reader key mismatch this item reported. hooks/session-continue.sh:58-59 confirms those are the read keys.
9c5d0ba74e79 | UPDATE | Primary claim LANDED: scripts/ship-land.sh now has a third state — GATE_KILLED (:206), exit 9 documented at :78-83 as "the suite died to a signal (or exited naming no failing test) and therefore is NOT red", plus the GATE-KILLED block at :670-682 which records that bats masks the signal. UNVERIFIED and probably still open: the `needs` addendum's fourth shape — ship-land ITSELF taking SIGTERM (rc 143) after a 26-min green gate, with no resumable record. :791 gestures at reaper coverage; re-scope the item to that half only.
091a590f738a | KEEP   | The hermeticity lint's rules are all ENV-seam rules (1/2/5a/5b/6); nothing in scripts/test-hermeticity-lint.sh addresses a suite SPAWNING the operator's live cc-dispatch via a real `cc-backlog add`. Only textual mentions of cc-dispatch exist (:62, :158, :347) and they are about CC_DISPATCH_LOG and an embedded selftest, a different question. 63bf5c56's hand fix is still the only defence.
b2775a8bbc3a | UPDATE | Rule 6 LANDED (5f772838, 08-09 00:46) and it is adjacent but NOT this — and the lint says so in its own words at :782-791: "A $HOME-ROOTED default is RULE 1's business and must never be claimed by rule 6 … That gap is real and is filed SEPARATELY". This item IS that filing, so it should now be written as rule 6's named exclusion rather than as a rule 5 widening, and it inherits rule 6's measured sizing lesson (READ-alone claimed 123 of 324 suites; the mechanism intersection is what made it shippable). The cc-reaper instance is already pinned (tests/cc-reaper.bats:36 exports CC_BEAT_DIR) — the class is not.
6a82c9405b9e | KEEP   | Both cases still assign unguarded under errexit — tests/unattended-sysctl-path.bats:74 and :89 are `out="$(env -i PATH=… bash "$QOS" --json --no-append 2>/dev/null)"`, so any non-zero exit from the census kills the test before its own message can run. The suite was last touched 4c58eaf5 (08-06), BEFORE the 08-09 measurement, so nothing has refuted it.
da4b516dc78a | UPDATE | Symptom real, DIAGNOSIS INVERTED — and this is the most useful correction in the slice. hooks/lead-crash-watchdog.sh no longer calls `ps aux` AT ALL: it was replaced by two `lcw_bounded … /usr/bin/pgrep -x` calls on 2026-08-07 (:987-997, with the load-781 rationale in the comment). tests/watchdog-census.bats:255 still iterates `for call in 'LCW_PYTHON_BIN' 'memory_pressure' 'ps aux' '"\$tdbin"'` and greps for `lcw_bounded [^|]*ps aux`, which now matches zero lines. So the census is red because its ANCHOR died when the subject got better — byte-for-byte the shape 911ccc8e fixed in runner-stdin-immunity. Remedy is to re-anchor on pgrep (and to assert the property, not the spelling), NEVER to wrap a `ps aux` that no longer exists.
c6f8553e16d5 | PRUNE  | Fixed by 3cb4fd28, which names this id in its trailer ("Filed as c6f8553e16d5") and reports the exact counters the item measured going 21 ok/1 not_ok -> 22 ok/0 not_ok, mutation-controlled both ways.
c2930ed4f50a | PRUNE  | Fixed by 911ccc8e (2026-08-09 01:15 PDT). G1's census floor and G4/G5's build_slg_probe anchored on `bats_green(){`, deleted on purpose by item 38e4601fa933 in favour of the three-state bats_row; the guarded property never changed (the successor still redirects at session-lifecycle-safety-gate.sh:71).
e3d4e7da8a1f | KEEP   | Newest measurement in the slice (2026-08-09 23:23Z, 28 min before trunk head) and only partly explained: iterm2-appname-lint's cause is 1a5f81c68100 (confirmed live above); permission-gate-lint reds AFTER d10bcd37 landed, so it has a second, unnamed cause; kitty-recovery-launch.bats has had no commit since 2026-08-05 and no diagnosis at all. Keep as the census row; the two undiagnosed suites are the work.
3be57ac682f8 | UPDATE | Half discharged: tests/handoff-fire-bang-quoting.bats:33 now exports CC_FIRE_CAPACITY_GATE=off, so the unpinned-suite half is done. STILL LIVE: `extra-bang` is emitted at scripts/handoff-fire.sh:5683 and _fire_gate_of (:493-503) maps only capacity|headroom, cloud-*, payload-* — extra-bang falls to `*)` and becomes its own gate name, which is what the census case reports.
149789b69fc4 | PRUNE  | Fully discharged, in two steps. All six ORIGINALLY named files are clear on trunk — bin/cc-reaper, hooks/validate-bash.sh, scripts/scratchpad-reaper.sh, scripts/store-bounds-census.sh carry reviewed exemptions in tests/tsv-field-collapse.bats' heredoc; dispatch-acceptance and terminal-bench were padded at the emitter. The six the `needs` note re-measured are clear too — branch-reaper, thrash-block-recover, unattended-path-lint exempted; bin/cc-queue, assignee-pane-residency, terminal-bench fixed at the emitter by 71e96bcb (08-07). The LAST offender was scripts/cloud-ceiling-probe.sh and c2ccbeb8 (08-09 02:31) discharged it, stating the guard "has been red on trunk naming scripts/cloud-ceiling-probe.sh" — singular. Guard 23 is green as of that commit.
e146d30857b4 | UPDATE | Its EVIDENCE is discharged (all six re-measured offenders cleared — see 149789b69fc4), but its CLAIM is structural and untouched: the guard is still whole-tree and still not a gate-select --direct edge, so a brand-new unpadded reader is exonerable-as-adjacent and lands still pass. Rewrite as the chokepoint-flip decision — the precondition it names ("only safe to flip once the guard is green") is now SATISFIED for the first time, which makes this newly actionable rather than stale.
```

## Master item(s)

### M-C-1 — Trunk's suite gives a verdict about the TREE, so the land rail stops being blocked by its own harness

**Encompasses:** e3d4e7da8a1f, 1a5f81c68100, 3709b1649792, da4b516dc78a, 4a74657d6088, cb9980e4b0e5,
087db20c3a24, 6a82c9405b9e, 26d4010f1b22 (+ merged a40afaee8d9c), 3be57ac682f8, e146d30857b4,
ad4743f9ee2c, 9c5d0ba74e79, dd76e48db6b2, b2775a8bbc3a, 091a590f738a, f6b460816387, c6a47d8c3ccb

**Why this is one effort.** Every one of these is the same defect wearing a different suite's clothes: **a
test's verdict is decided by something that is not the tree** — the harness (a dead anchor, an unstubbed
helper, a fixture the sibling lint reads as production), the box (wall-clock bounds, live process
population, ambient env), or the gate's own selection logic. It is not an inference; the five commits that
landed on 2026-08-09 each say it in their own subject line, and my three UPDATEs re-diagnose three more
items into the same class (da4b516dc78a dead anchor, 4a74657d6088 harness not plist, 3be57ac682f8
half-pinned). The pruned items are the proof the class is tractable: five of them died in one 3-hour
window to one author working exactly this way — one red, one root cause, one mutation-controlled commit.

**Impact, argued from evidence.** This is the land-rail multiplier and nothing else in the slice competes.
A pre-existing red blocks *every* author's land touching bin/, hooks/ or scripts/ (1a5f81c68100 and
c6f8553e16d5 both say so, and 3cb4fd28 measured the cost: "blocked EVERY land touching those three dirs"
for 30h because the postland verifier that would revert it produced no GREEN stamp). It also closes the
second-order damage: 8 of the 40 items in this slice carry the `persistent thrash — claim→reopen /
land-conflict rebase-exit-5` needs-note, i.e. workers that could not land *at all*. Retiring it retires 18
items here plus whatever the other clusters hold, and it touches the enforcing surface (`ship-land.sh`,
`gate-select.sh`, the ratchets) rather than docs.

**DoD.** Every suite named above is green on a clean `git archive origin/main` tree at ordinary load, each
fix mutation-proven (delete the property, the case goes red) and landed one-per-commit; the two wall-clock
classes are converted to deterministic waits across the 19-file census, not enlarged; `gate-select`'s
delete rung and the tsv guard's chokepoint decision are landed; and a fresh full-suite run on trunk names
zero pre-existing reds.

**Falsifier.**
`cd /Users/chrisren/Development/claude-infrastructure && git show origin/main:tests/watchdog-census.bats | grep -q "'ps aux'" && exit 1; git show origin/main:scripts/permission-gate-lint.sh | awk '/\^\[\[:space:\]\]\*case\[\[:space:\]\]/{f=1} END{exit !f}' && exit 1; exit 0`
(exit 0 ⇒ the two anchor defects this effort is named for are gone; run the full census before trusting a
single green.)

**First move.** `da4b516dc78a` — it is the cheapest and it re-teaches the class: re-anchor
tests/watchdog-census.bats:255 on the pgrep calls the death path actually makes (hooks/lead-crash-watchdog.sh
:987, :996), assert the *property* (every death-path external is under lcw_bounded) rather than the
spelling, and mutation-prove by dropping one `lcw_bounded` prefix. It is ~5 lines and it produces the
template every other item here reuses.

**Order.**
1. da4b516dc78a (dead anchor — template) → 2. 1a5f81c68100 (pinned detector-file exclusion; unblocks
bin/+scripts/ lands) → 3. 3709b1649792 (one-line `case` depth leak; it currently mis-blocks lands) →
4. 4a74657d6088 + cb9980e4b0e5 (re-measure now that rules 1/6 landed) → 5. 087db20c3a24 (prefix-bisect the
polluting test — the only one needing a real bisect) → 6. e3d4e7da8a1f (diagnose kitty-recovery-launch and
permission-gate-lint's *second* cause) → 7. 26d4010f1b22 + a40afaee8d9c (19-file deterministic-wait sweep)
→ 8. 6a82c9405b9e (guard the two `out=$( )` assignments) → 9. 3be57ac682f8 (map extra-bang in
_fire_gate_of) → 10. dd76e48db6b2 → 11. b2775a8bbc3a → 12. 091a590f738a (the three ratchet holes, in
sizing order; b2775a8bbc3a needs its own staged allowlist) → 13. f6b460816387 + c6a47d8c3ccb (scope the
two whole-tree lints to the diff) → 14. ad4743f9ee2c + 9c5d0ba74e79 (gate verdict correctness) →
15. e146d30857b4 (flip the tsv guard to the always-run phase — its precondition "guard is green" is
satisfied for the first time as of c2ccbeb8).

### M-C-2 — A fired pane's launch intent and its back-channel are provably deliverable, and the bounds that judge them are honest

**Encompasses:** e677db9bb7c1, 07ac6d58d88d, bacdfc4f63ab, f660a37851cd

**Why this is one effort.** One surface (the fire/deliver path: `handoff-fire.sh` → `it2-kitty` →
`cc-pane-runner` → `cc-pane send` / `cc-notify`) and one root cause: **a delivery record is trusted for
its presence rather than its provenance or its resolvability.** `CC_PANE_CMD` non-empty is read as intent
(it2-kitty:638); `cc-notify <token>` matching a regex is read as a resolvable target (payload-lint F3);
`cc-pane send` is trusted to have typed what it sent (no echo-verify); and verify_engagement's window is
trusted to be 120s when it is a sleep count that measures nothing. Fix one and the others remain
individually shippable, which is why this is a coherent second effort and not a split of M-C-1.

**Impact.** Lower than M-C-1 and honestly so — it does not block lands. It does cause silent
wrong-work: a duplicate agent session nobody dispatched (e677db9bb7c1, proven with a fake kitty), a
successor that is fired and can never report back (bacdfc4f63ab, the W5 root reached *through* a green
lint), and a 12-15 minute fail-loud verdict that outlives every caller (f660a37851cd, disk-proven against
handoffs.jsonl). Half of e677db9bb7c1 already landed, so this starts from a shorter runway than its item
count suggests.

**DoD.** Pre-delivery requires a paired opt-in signal rather than non-emptiness, with the argv suite arm
beside tests/it2-kitty-argv-spawn.bats; F3 calls `cc-notify --resolve` instead of re-implementing it;
`cc-pane send`'s contract is decided and either split or routed through a verified-typing helper (and the
typed-send-lint grandfather line deleted); verify_engagement has a true wall-clock deadline whose default
preserves today's effective window, with a test that can see the 40× multiplication.

**Falsifier.**
`cd /Users/chrisren/Development/claude-infrastructure && git show origin/main:scripts/payload-lint.sh | grep -q -- '--resolve' && ! git show origin/main:scripts/typed-send-lint.sh | grep -q 'bin/cc-pane::drv_iterm2_send'`

⚠️ **Second conjunct was `| grep -qv …` until 2026-08-19 — vacuous, for the reason pinned at
`docs/research/codex-probe-screen-2026-08-10/screen-mailbox-forward.md:9`: `grep -qv` exits 0 the
moment any ONE line fails to match, so "the grandfather line is deleted" passed whether or not it
was. `! … | grep -q` is the shape that asserts absence. Corrected in place; nothing else changed.

**First move.** `bacdfc4f63ab` — replace F3's regex with a `cc-notify --resolve` call. It is the smallest
diff, it deletes a re-implementation rather than adding a mechanism, and it is the one whose failure mode
(a successor that cannot report) silently costs whole sessions.

**Order.** 1. bacdfc4f63ab → 2. e677db9bb7c1 (producer-side opt-in + the missing suite arm; the consumer
unset already landed) → 3. 07ac6d58d88d (contract decision, then the ratchet line goes) → 4. f660a37851cd
(deadline + cheap oracle + a test that can see it).

### M-C-3 — A backlog item's premise is re-read at consumption, so a worker is never handed a cure that already landed

**Encompasses:** f46261b23ec2, 7174eb206d25, 5d0cfc272c4b, 043c2e5fcc7e (merged)

**Why this is one effort.** All three live items are one loop on one path (`cc-backlog unblock` →
`cc-dispatch` → worktree → land): **the item's evidence is frozen at `add`, the worktree it is dispatched
into is frozen at first claim, and neither is re-read.** They compound rather than merely co-occur — a
stale worktree makes the land fail, the failed land reopens the item, the reopen re-dispatches the same
stale evidence into the same stale worktree. That is the closed loop 5d0cfc272c4b measured, and it is why
both present as "persistent thrash".

**Impact, and this is the measured part.** My slice IS the evidence: **7 of 40 items (17.5%) were already
fully cured**, several by commits that landed *before* the item was last touched — 6783af2685ba's cure
landed 2026-08-08 17:17 and the item was re-touched 2026-08-09 19:59; fe21305312ec's two cures both landed
while the item sat blocked since 07-26. A further 11 (27.5%) carry facts stale enough to send a worker at
the wrong thing (da4b516dc78a would have had someone wrap a `ps aux` that does not exist). **45% decay,
and every point of it is a burned dispatch slot on a machine that has panicked 4× this week.** 8 of these
40 items also carry the thrash needs-note that 5d0cfc272c4b explains, so this effort is what makes the
other two efforts' items dispatchable at all.

**DoD.** `unblock` and `fire` re-validate the item's cited paths/shas/symptoms and fail **OPEN** with the
staleness surfaced in the brief (never a refusal — per the discovery-critic re-check-at-consumption rule);
a claimed per-item worktree is fast-forwarded to origin/main and refused if its index is dirty (or the
name is made unique per attempt); and the brief's provenance clause carries a timestamp so a worker can
tell a fresh measurement from a 7-day-old one.

**Falsifier.**
`cd /Users/chrisren/Development/claude-infrastructure && git show origin/main:bin/cc-dispatch | grep -q 'rev-list --count HEAD..origin/main' && git show origin/main:bin/cc-backlog | grep -q 'revalidate'`

**First move.** The cheap detector 5d0cfc272c4b already specifies, because it is read-only and provable
today: at dispatch, assert `git -C <wt> status --porcelain` is empty AND `rev-list --count
HEAD..origin/main` is 0, and log the refusal. Run it once across `~/Development/.worktrees/` to size how
many dispatch targets are currently poisoned before changing any behaviour.

**Order.** 1. 5d0cfc272c4b detector (read-only sizing) → 2. 5d0cfc272c4b remedy (FF-or-refuse, or
per-attempt names) → 3. f46261b23ec2 (re-validate at unblock/fire, fail-open + timestamped provenance) →
4. 7174eb206d25 (the re-judgment discipline for items whose symptom vanished — mutation, not rebaseline).

## Notes for the lead

**1. Six KEEP/UPDATE items in my slice are not test-corpus and I did not fold them.** Forcing them into a
master would produce a list, which the contract forbids. Each is verified and needs a home:

- `5ef317c7aa37` (execution-locus enforcement, PreToolUse matcher) → orchestration/hooks cluster. Verified
  live; its stated blocker (no per-phase dispatch record) makes it *not startable* until a plan-to-work
  store exists — worth telling whoever owns plan granularity.
- `0488b0e1e423` + `170a3b38f8c9` (setup-token) → accounts/auth cluster. These two are one item now: the
  loader landed, only the operator-TTY mint and the 4 scope tests remain. `0488b0e1e423` is genuinely
  operator-only (real TTY) — it belongs in the `cc-backlog needs` operator queue, not a dispatch slot.
- `329dd6350eb3` (cloud create intermittent) → cloud/venue cluster; its premise predates ca7db1a1 and must
  be re-measured, not worked.
- `7c266e16fc94` (MEMORY.md over budget) → memory-hygiene; human-gated by construction (`/compact-memory`
  is propose-only), so it is a `needs`, not agent work. It regressed to 26,382 B — it is truncating today.
- `130814a95132` (cloud-ceiling-probe pipefail) → could ride M-C-1's ratchet work, but its real home is
  wherever `3dcac1f3`'s pipefail lint lives, because the finding is about **that sweep's triage rule**,
  not about this file (see below).

**2. Cross-cluster landmine — the pipefail sweep has a documented blind spot and someone should hear it.**
`3dcac1f3` closed 22 sites and grandfathered 30, on the measured rule *"a single write under the 64 KiB
pipe buffer is safe"*. `130814a95132` measured the counter-example on this very tree: a single-write
producer whose payload is a 180s PTY capture goes FALSE at exactly 64 KiB (1/100) and 0/200 above it. Any
cluster holding pipefail work should treat "single-write ⇒ latent" as **size-conditional**, and the lint
should flag single-write producers whose source is unbounded.

**3. Duplicate pair inside my slice, both now dead:** `971995a07b05` and `c6f8553e16d5` are the same AC22
finding filed twice by two hosts (69134, 40483) hours apart — a second instance of the duplicate-filing
shape `f46261b23ec2` describes. If another cluster holds a third copy, the same commit (`3cb4fd28`) prunes
it.

**4. The `wasDone: true` on `149789b69fc4` is trustworthy here, unusually.** I verified the completion by
content, not by the flag: every file both its title and its `needs` note name is discharged on
origin/main. Its long `needs` note (close the duplicate worktree sessions) is separately stale — the refs
it says to recover from still exist (5,484 wip/checkpoint refs on this repo), but the work they hold was
the fix that landed. Do not re-dispatch the cherry-pick.

**5. What I could NOT do, stated plainly.** No suite was run, so every "still red" verdict is *"the defect
the item names is still present in the tree"*, never *"I observed the red"*. Two items rest on that
distinction: `cb9980e4b0e5` (a deployed-layer verdict no git read reproduces) and `e3d4e7da8a1f`'s
kitty-recovery-launch row (no diagnosis exists to check against). Both are KEEP for that reason and both
would be settled by one targeted bats run when the box is quiet.
