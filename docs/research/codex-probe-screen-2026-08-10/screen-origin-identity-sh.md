VERDICT: CLEAN

EVIDENCE:

1. THE STATE ENUM AND ITS FALL-THROUGH DEFAULT (`fired_stamp_tenancy` :139-160, `oi_origin_class` case :185-198).
   The header names FIVE states (absent|valid|spent|stale|unknown) and `oi_origin_class`'s `case` has
   only FOUR arms plus no `*)` — the classic shape of "a state enum with a member that falls into a
   fail-open default". I sourced the lib and drove all five states from real fixtures under bash
   (probe1): open/matching-cwd => valid, closedAt-set/matching-cwd => spent, cwd=B while here=A =>
   stale, missing + zero-byte stamp => absent, and {no .cwd field, malformed JSON, cwd since deleted,
   CC_SELFCLOSE_TENANCY=0} => unknown. The missing arm is `absent` DELIBERATELY, and it falls into the
   by-cwd recovery block whose every exit is `origin`. Measured verdicts: valid=>fired-peer,
   spent+my-marker=>fired-peer, spent+foreign-marker=>origin, spent+no-transcript=>origin,
   stale=>origin, unknown=>origin, absent-no-index=>origin. `origin` is the CONSERVATIVE side for this
   consumer (it subjects the session to the close contract), so the default is fail-CLOSED, not open.
   A hypothetical sixth state would land there too.

2. THE PROBE ON A NEGATIVE / LOOKUP MISS READ AS ABSENCE (`oi_origin_class` :200-217).
   This is the exact class the file's own header says the by-cwd index was built to fix, so I attacked
   the fix. A miss is never taken as proof: I built the resume-loses-pane-id fixture (open stamp under
   pane 353, index pointing at it) and confirmed pane='' and pane=NEWID both classify fired-peer ONLY
   when the marker is in MY transcript; the operator-pane-in-the-peer's-worktree negative returns
   origin. I then attacked the pointer itself: a pointer to a CLOSED record => origin; a pointer to a
   record whose own `.cwd` is a DIFFERENT worktree (liar pointer) => origin; a pointer to a
   nonexistent stamp => origin; marker field deleted or empty-string => origin; transcript path that
   is a directory or does not exist => origin. Every one of those is a lookup miss, and every one lands
   on the safe verdict, because the block re-validates `closedAt`, re-resolves `.cwd`, and demands a
   positive `grep -qF` before it will emit `fired-peer`. The index is only the FINDER; the marker is
   the PROVER, exactly as the comment claims.

3. `[ A ] && [ B ]` AND-ABSORPTION AND SWALLOWED FAILURES — checked whether `set -e` is even in force
   first. It IS in one consumer: scripts/handoff-fire.sh:257 is `set -euo pipefail` and sources this
   lib; hooks/completion-assert.sh:96 is `set -uo pipefail` (no -e, stated reason at :88). The only
   bare and-list in the file is `[ -n "$pane" ] && state="$(fired_stamp_tenancy ...)"` (:184) — every
   other guard is `[ A ] && [ B ] || { ...; return; }`, whose `||` carries the status. I sourced the
   lib under a real `set -euo pipefail` and called every function on its failing paths, including
   `oi_origin_class ""  "$A" "$tp"` bare (not in an if-condition): all returned rc=0, nothing aborted,
   and the empty-pane case correctly left state=absent and fell to the by-cwd path (probe2, "ALL
   SURVIVED"). The `[ -n "$pane" ]` failure is the non-final command of an && list, so `set -e` exempts
   it — verified empirically, not assumed. `printf 'origin'; return 0` and each arm's explicit
   `return 0` mean no caller can ever read a stray non-zero as a verdict.

4. THE VERDICT-TOKEN AND KILL-SWITCH COUPLING (`fired_stamp_tenancy` :140, :155-159; header :177-182).
   `closed="$(jq -r '.closedAt // "null"' "$stamp" 2>/dev/null || echo x)"` — I confirmed the `// "null"`
   + `|| echo x` pair lands every unreadable answer on `spent` (malformed JSON => unknown before this
   point; an unreadable closedAt => x => spent), i.e. the refusing side for the self-close gate and,
   via the marker re-check, `origin` for this one. `spent` and `stale` are the only tokens that can be
   emitted without reading the transcript, and neither certifies anything: both mean REFUSE downstream.
   `fired-peer` (the exempting token) is only ever reached from `valid` (id + cwd + open, the
   pre-existing documented positive) or from a positive marker grep. I also drove the R8 switch:
   CC_SELFCLOSE_TENANCY=0 gives `unknown` for every existing stamp and `absent` for a missing one —
   which is precisely the "restores the pre-tenancy answer for every state" the comment claims — and
   through oi_origin_class it degrades a valid stamp to `origin` (over-blocking, bounded), never to a
   silent exemption. The `!= 0` idiom matches its sibling seam CC_SELFCLOSE_ADOPT
   (scripts/handoff-fire.sh:2819), so it is the repo convention, not a one-off spelling denylist.

ALSO VERIFIED, NOT CONVICTED:
 · Header claim that `by-cwd/` is invisible to the three store enumerators: all three really are
   non-recursive globs (`for f in "$FIRED_DIR"/*.json` at bin/cc-classify:444,
   scripts/handoff-fire.sh:3086, scripts/desk-invariant.sh:291) — no reader uses `find`. Confirmed by
   listing the store after writing an index: only pane-keyed files appear. The comment's cited line
   numbers have drifted (:406 vs 444, :288 vs 291); that is a comment inaccurate about a NEIGHBOUR,
   the behaviour it asserts is correct, so it is not a defect.
 · Marker over-match: `grep -qF --` is literal, and FIRE_MARKER is minted inside handoff-fire
   (:6620) and written ONLY into the composed prompt file (:6621) — it is never echoed to stdout/stderr,
   so a fired peer's marker cannot leak into the ORIGINATOR's transcript via the tool result and
   mis-certify an origin session as a peer. I grepped every FIRE_MARKER emission to confirm.
 · `${here:-.}` in fired_stamp_tenancy (:151): with an empty cwd the compare uses the process cwd. Both
   real callers pass non-empty (handoff-fire :5022/:5039/:5146 pass "$PWD"; completion-assert :669
   passes "$CWD"), and for a Stop hook the process cwd IS the session cwd, so the fallback cannot
   manufacture the exempting answer. Measured: empty `here` yielded `stale` (=> origin), the safe side.
 · shasum is unguarded where jq is guarded: with shasum removed from PATH, `write_fired_cwd_index`
   exits 127 under `set -euo pipefail` instead of its documented "always 0" (probe4, OUTER RC=127).
   Not convicted: shasum is a DECLARED dependency (header :35), the condition is a missing coreutils/perl
   binary, and the failure is fail-LOUD (the fire aborts) — it produces no wrong verdict and cannot
   silently exempt anything. Reporting it as a defect would be manufacturing a marginal finding.
 · shellcheck -s bash: clean (rc 0). Existing suites tests/origin-identity.bats and
   tests/handoff-fired-cwd-index.bats: all green. Working tree is identical to origin/main for this file.

OPEN_FINDINGS: none found; searched docs/**, all *.md in the repo (excl. node_modules), and the owning
plan docs/plans/CLOSE_INTEGRITY_2026-08-10.md, for "origin-identity", "oi_origin_class",
"fired_stamp_tenancy", "read_fired_cwd_index" and for OPEN/defect language attached to them. Every hit
is descriptive (plan §W1 line 78 records the extraction; line 8 records the suite green; CLAUDE.md:374
and commands/wrap.md:84 cite the lib as the origin oracle). No doc names a defect in this file.
