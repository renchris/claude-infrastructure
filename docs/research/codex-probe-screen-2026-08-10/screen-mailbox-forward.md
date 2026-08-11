VERDICT: DEFECTIVE

EVIDENCE:

1. VACUOUS negative assertion — tests/mailbox-forward.bats:78, in `@test "migrate moves exactly the UNCONSUMED (acked, EOF] window, with provenance"`:

    grep -qv 'l1' "$CC_MAILBOX_DIR/$B.md"          # consumed lines are NOT re-delivered

`grep -qv PAT FILE` exits 0 as soon as ANY ONE line fails to match, so it cannot detect the regression its comment claims. In the exact failure mode being guarded (migrate re-delivering from `seen`/line 0 instead of `acked`), `$B.md` would contain `...l1`, `...l2`, `...l3`; the `l3` line still does not match `l1`, so `grep -qv 'l1'` still exits 0 and the test still passes green. The assertion can only fail if EVERY line contains `l1`, which cannot happen given the fixture. The correct shape is `! grep -q 'l1' ...`.

This is not a stylistic nit — it is the repo's own explicitly documented anti-pattern, called out by name in three sibling suites:
  - tests/postland-verify.bats:1168-1170 — "`! grep -q`, NOT `grep -qv`: with -v a MULTI-LINE input passes as long as ONE line is clean"
  - tests/cc-backlog.bats:1258 — "NOT `grep -qv` (passes whenever ANY line fails to match…)"
  - tests/kitty-recovery-launch.bats:122 — same warning
and the repo uses `! grep -q` 217 times. The file's own header rule 2 ("Assert the SPECIFIC value, never a loose glob a degraded result also matches") is violated by its own line 78.

Aggravating, not exculpating: line 76 (`grep -c '' … -eq 1`) does independently pin the no-re-delivery property, which means line 78 is a pure always-green line whose comment overstates what it measures. A reviewer reporting line 78 is reporting a real, repo-convention-recognised vacuous pass, so this brief cannot serve as a negative control.

2. (Secondary, would also be genuinely reported) Title asserts a specific the body does not measure — tests/mailbox-forward.bats:36-45:

    @test "a CYCLE terminates at the last good hop instead of spinning …"
    …
    [ "$status" -eq 0 ]
    [ -n "$output" ]

"terminates at the LAST GOOD HOP" is measurable — for A→B→C→A the implementation (hooks/lib/mailbox-pending.sh:389-403, visited-set break) returns exactly `C`. The body only asserts non-empty, which a fully degraded result (`A`, i.e. the pointer chain silently not followed at all) also satisfies. Contrast the sibling bounded-hops test at line 47-56, which correctly pins `[ "$output" = "00000002-…" ]`. Same file, same property, one pinned and one loose — the loose one is the defect.

Places I probed hardest that ARE sound (so they are not counted against it):
- line 87 `-eq 2` "NOT 4" and line 108 `-eq 2`: exact counts, but here growth IS the regression (duplicate delivery / clobbered successor mail), so `-ge` would be strictly wrong. Correct use of `-eq`.
- lines 47-56 bounded-hops: `CC_MBX_FORWARD_MAX_HOPS=2` is set BOTH as a `run` prefix (which would be inert) and inside the `bash -c` string (which is what actually binds), and the expected head `00000002-…` matches `printf '%08d'` with i=2 — the assertion genuinely reds if the hop cap regresses.
- lines 58-61 / 63-67 negative probes (junk pointer, self-forward) are each paired with a positive control earlier in the file (lines 30-34 write and follow a valid chain), and the self-forward test pins both `status -eq 1` and pointer-file absence.
- `local prev/nxt` at line 48 is legal (bats test bodies are functions); all `[ ]` are plain test builtins under bats' `set -e`, no `[[ ]]`/`(( ))` deadness, no `[ A ] && [ B ]` absorption.

OPEN_FINDINGS: none found; searched docs/research and docs/plans for "mailbox-forward" — 5 hits, all non-defect: docs/research/orphan-harvest-2026-07-26/r1-impact-map.md:31 (naming-map coverage), r4-runtime-profile.md:236 (runtime row, "pass"), docs/research/infra-reliability-audit-2026-07-22/raw/a5.md:43 (cites mailbox-forward.bats:81-88 as EVIDENCE that migrate is idempotent, not as a finding), docs/plans/TWO_WAY_SESSION_COMMS_PLAN.md:482 and docs/plans/CROSS_SESSION_COMMS_V2.md:428 (suite inventory / re-run log). No doc names a defect in this file — the defect above is unlogged.
