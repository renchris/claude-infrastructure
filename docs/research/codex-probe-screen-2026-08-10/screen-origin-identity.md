VERDICT: CLEAN

EVIDENCE:

Probed hardest, and why each is actually sound:

1. The six `⇒ origin` negatives (lines 80, 86, 91, 103, 110, 117) against the fact that `origin` is
   oi_origin_class's fall-through default (hooks/lib/origin-identity.sh:221). This is the classic
   always-green shape: a lib that returned `origin` unconditionally would pass all six. It is NOT
   vacuous here because three positives sit in the same file and would go red — line 71
   (valid ⇒ fired-peer), line 77 (spent+marker ⇒ fired-peer), line 100 (absent+index+marker ⇒
   fired-peer) — and each negative has its paired positive one to three tests away
   (80/86 ↔ 74; 103/110 ↔ 96; 91 ↔ 69). Repo convention "every negative probe paired with a
   positive" is met test-by-test, not just suite-wide.

2. Live-ness of the four load-bearing branches, verified by mutation (functions re-sourced from a
   sed-transformed copy in memory via eval; nothing written, repo untouched):
     · collapse `spent`→`valid` in fired_stamp_tenancy:154 ⇒ tenancy flips to `valid` and the
       line-83/88 fixtures flip to `fired-peer` — reds tests 3, 9, 10 and the CONTROL at 127.
     · replace the spent-arm marker grep (oi_origin_class:192) with `true` ⇒ line-83 fixture flips
       to `fired-peer` — reds test 9.
     · replace the by-cwd-arm marker grep (:214) with `true` ⇒ line-107 fixture flips to
       `fired-peer` — reds test 13.
     · replace the by-cwd `[ "$closed" = null ]` guard (:209) with `true` ⇒ line-114 fixture flips
       to `fired-peer` — reds test 14.
   Every asserted verdict is causally attached to a distinct guard. No assertion survives its own
   subject's removal.

3. The fixtures, against "a state that never occurs in production". `stamp()` (line 27) writes
   {paneUUID, cwd, selfRetire, closedAt, marker} — a strict projection of the real v2 record written
   by mark_fired_peer (scripts/handoff-fire.sh:2563-2580, which emits closedAt:null and marker on
   every fire). The lib reads only .cwd/.closedAt/.marker, so the minimal record is faithful, and
   omitting `marker` when empty is jq-indistinguishable from production's `marker:null` under
   `.marker // ""`. Critically, the by-cwd pointer in tests 12/13/14 is NOT hand-rolled: line 98/104/112
   call the real `write_fired_cwd_index`, so the index shape cannot drift from the reader. The
   351-stamp/353-query pane pair is the exact id-renumber incident the lib header records
   (measured 2026-08-07), not an invented state.

4. Shell-shape traps. There is no `[ A ] && [ B ]` and-absorption anywhere: the CONTROL at 127
   deliberately splits its two verdicts into two separate `[ ]` statements (132, 133), each of which
   fails the test independently under bats' set -e. No `[[ ]]`, no `(( ))`, no `! cmd`. Both `run`
   uses (line 58) and every `$(call ...)` assert on captured OUTPUT with an exact string compare, so
   the fact that these functions are documented "always rc 0" cannot hide a failure — a crashed call
   yields "" and `[ "" = unknown ]` is red. setup()'s `grep -q '^oi_origin_class() {' "$LIB"` (line 23)
   is a real artifact control: it hard-fails every test if the lib is missing or stubbed, and
   fired_stamp_tenancy's own existence is transitively pinned by the six tenancy tests.

Also checked and clean: no count assertions at all, so the `-ge`-over-`-eq` convention is not engaged
and there is no growth-reds-on-addition shape; no assertion greps the tree or a neighbour's subject
(every probe targets exactly the one function named in its title); no empty-output case reading green;
BATS_TEST_TMPDIR is per-test on /Users/chrisren/.claude/bin/cc-bats 1.13.0 (bats-exec-test:69 keys it on BATS_SUITE_TEST_NUMBER), so
test 15's "no index" premise is genuinely fresh and no earlier test's stamps leak forward. Suite runs
17/17 green as-is.

One non-defect noted for completeness: the schema-1 kill-switch stamp (CC_LIFECYCLE_RECORD=0,
handoff-fire.sh:2551) has no closedAt field at all and would read `valid` — that is the correct
pre-tenancy semantics and is simply an untested state, i.e. a coverage gap, not a wrong or vacuous
assertion in this file.

OPEN_FINDINGS: none found. Searched docs/research/ and docs/plans/ (recursive, case-insensitive) for
"origin-identity", "origin_class", "oi_origin_class", "fired_stamp_tenancy". The only hits are in
docs/plans/CLOSE_INTEGRITY_2026-08-10.md — lines 6, 8 and 78-79 — and all three are positive: the W1
landing commit `277323b8`, "Suites green this session: origin-identity 17", and the extraction spec.
docs/research/BATS_DEAD_ASSERTIONS_2026-07-25.md does not name this file.
