VERDICT: DEFECTIVE

EVIDENCE:

1. `session_unlanded_mine`, lines 308-314 — a failed/timed-out `git diff` is returned as the NEGATIVE
   verdict "not mine" (rc 1) instead of cannot-tell (rc 2).

       while IFS= read -r f; do
         [ -n "$f" ] || continue
         printf '%s\n' "$out" | grep -qxF "$top/$f" && return 0
       done <<EOF
   312: $( cd "$top" 2>/dev/null && _sw_bounded 5 git diff --name-only "$trunk"..HEAD 2>/dev/null )
       EOF
   314: return 1

   The command substitution sits inside a heredoc, so the git exit status is structurally
   unobservable and is discarded; any failure (unresolvable `$trunk`, the 5 s `_sw_bounded` timeout,
   any git error) yields an empty list, the loop body never runs, and the function falls through to
   `return 1` — a lookup MISS read as an ABSENCE, which is the exact doctrine this file's own header
   states at lines 25-28 ("A lookup that fails can only MISS, and a miss is not an absence … rc 2
   cannot-tell — no jq / no transcript / read error / timeout") and which its docstring at line 280
   re-promises ("rc: 0 mine · 1 not mine · 2 cannot-tell").

   EXECUTED, not reasoned. Fixture repo + fixture transcript, lib sourced under `set -uo pipefail`
   (the consumers' flags):
     · real git, real trunk, a path this session wrote → rc 0 (positive control passes)
     · `session_unlanded_mine <tp> <repo> nosuchref` → rc 1   (expected 2)
     · git shimmed so `diff --name-only` sleeps 30 s → returns after 5.2 s with rc 1 (expected 2)

   It is a behavioural defect, not a comment inaccuracy, because the rc is consumed verbatim as a
   verdict: hooks/completion-assert.sh:326 `session_unlanded_mine "$TP" "$CWD" "$trunk" >/dev/null
   2>&1; return $?` — rc 1 EXONERATES the CLOSE_INTEGRITY W2b unlanded term (the close stops being
   blocked), whereas rc 2 is documented three lines above as "cannot-tell — stay strict". So the
   swallowed failure flips the gate from strict to pass, silently and in the fail-green direction.

   The asymmetry is internal to this file and settles intent: every other external read here converts
   failure to rc 2 — line 175/177 (`git rev-parse … || return 2`), line 121 (`[ "$rc" -eq 0 ] ||
   return 2` for jq), and above all the sibling `session_dirty_mine` at lines 252-254, which runs the
   same class of git read in an explicit `if ! ( … ) >"$tmpf"; then rm -f "$tmpf"; return 2; fi`.
   Line 312 is the one git read in the file whose failure is not converted.

   Reachability note, stated honestly: `wrap-ledger.sh:171` verifies TRUNK resolves before publishing
   it and both current callers reject ''/none, so the bad-ref trigger is largely closed off THROUGH
   THOSE TWO CALLERS. The timeout trigger is not closed off — `_sw_bounded` exists precisely because
   these reads can wedge on a Stop hook — and this is a public SSOT lib whose declared contract any
   third caller will rely on.

2. Secondary, same swallowed-failure class, measured and scale-bounded (reported for completeness,
   subordinate to #1): lines 269 and 310 use `printf '%s\n' "$mine" | grep -qxF "$abs"` under
   consumers that set `set -o pipefail` (completion-assert.sh:96, operator-readout.sh:121,
   teammate-auto-shutdown.sh:45). When `$mine` exceeds the pipe capacity and grep -q short-circuits
   on an early match, printf dies of SIGPIPE and pipefail hands back rc 141 for a match that DID
   occur — the hit is dropped, fail-green. Measured on this machine: rc 0 up to 42 093 bytes,
   rc 141 at 85 293 bytes; threshold ≈ 64 KB ≈ 2 400 unique written paths, so it needs a very large
   session. This is the identical shape peer-owned.sh:118 documents as having already cost this repo
   a false precondition failure (53d45a09), and which it avoids by short-circuiting inside jq.

   NOT convicted (checked and cleared): `[ A ] && [ B ]` / `&& return 0` absorption — no consumer
   sets `-e` (completion-assert.sh:88 and session-continue.sh:35 refuse it deliberately), so lines
   215-216, 274, 295-296 are sound.

WHAT ELSE I PROBED HARDEST AND CLEARED (all executed against real fixtures, not reasoned):
  · Three-state contract of `_sw_paths`: empty transcript → rc 1; unparseable line → rc 2; missing
    file → rc 2; empty arg → rc 2. No vacuous pass.
  · Turn boundary jq: last-turn-conversational → turn rc 1 while session rc 0; a `tool_result` user
    record does NOT reset; a sidechain user record does NOT reset but its write still counts;
    `NotebookEdit`/`notebook_path` and MultiEdit both resolved. Verified live.
  · `session_dirty_mine` porcelain parsing: `git status --porcelain -z -uall` verified by `od -c` to
    emit `R<sp><sp>new\0old\0` with R at index 0, so `case "$rec" in [RC]*)` covers it and the
    skip-check-before-case ordering means an old-path record beginning with R/C cannot cascade.
    Untracked NEW directory (`newdir/mine.ts`) and a path with a space both intersected correctly.
    A worktree-only rename does not produce ` R` on git 2.54 (it is ` D` + `??`), and even if it did
    the mangled old-path record can only miss, never false-hit.
  · Canonicalisation: symlinked checkout spelling in the transcript still intersects (rc 0, correct
    relative path); sibling-only dirt → rc 1; missing transcript → rc 2 propagates through the
    intersection; a file already committed → rc 1.
  · `session_wrote_here_this_turn` repo bound: write in another tree → rc 1; write inside cwd → rc 0;
    unresolvable repo_dir → rc 2 (no silent unscoped widening); omitted repo_dir → rc 0 with the turn
    bound only, exactly as documented.

OPEN_FINDINGS: none found. Searched `docs/` (grep for session-writes / session_dirty_mine /
session_wrote_here_this_turn / session_unlanded_mine) — all 20+ hits are design/plan prose citing the
lib as the working SSOT (docs/plans/SUBAGENT_STOP_HOOK_LOOP.md, CLOSE_INTEGRITY_2026-08-10.md,
TEAMMATE_SELFCLOSE_INVESTIGATION.md, docs/research/kitty-selfclose-chain-2026-08-04.md:153 explicitly
says "the attribution is correct — only its plumbing was dropped"), plus a PRUNEd backlog entry
(backlog-consolidation-2026-08-09/OUT-session.md:212, closed as LANDED). Also checked
`git log origin/main -- hooks/lib/session-writes.sh` (4 commits, all fixes already applied) and
`tests/session-writes.bats` (24 tests incl. 5 mutation controls) — no test exercises a FAILING
`git diff` in `session_unlanded_mine`, which is why defect #1 has no control catching it.
