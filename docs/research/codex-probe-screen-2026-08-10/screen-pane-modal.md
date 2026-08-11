VERDICT: CLEAN

EVIDENCE:

1) The anti-rot arm (L248-262) and its mutant control (L264-272) — the classic vacuous-grep site.
I re-ran the arm's substance by hand against the binary the helper actually resolves. `claude_binary`
(L219-239) is a numeric max over `$REAL_HOME/.claude-[0-9]*`; on this box that set is exactly
156/161/170/183/219/220 (verified by ls), the `case ''|*[!0-9]*` filter is correct bash and also
eats the unmatched literal glob, and `/Users/chrisren/.claude-220/.../bin/claude.exe` exists. All 8
fragments produced by `modal_fragments` (the 4 patterns `tr '|'`-split) are PRESENT in that binary,
and the control's string `Do you trust the files in this folder` is ABSENT — so the loop is neither
inert nor always-matching, and it is not skipping. Two structural traps are avoided: the accumulator
runs under `<<<` (herestring, current shell) not a pipe, so `missing` survives; and
`grep ... || missing=...` keeps errexit off the failing grep while still reaching `false` at L261.
The control's `[ "$status" -ne 0 ]` does conflate "no match" with "grep errored", but it cannot go
falsely green in isolation: an unreadable/wrong `$BIN` makes the *main* arm report all 8 fragments
missing and red, so the pair is mutually guarding.

2) The RED-PROOF / POSITIVE-CONTROL pair (L100-119) — the load-bearing negative.
L100 asserts prose carrying BOTH halves is not a modal; on its own that is exactly the shape that
"cannot fail" if the matcher were broken open. It is paired at L110 with the same input under
`.*`-prefixed patterns, which fires (status 0, slug `mcp-trust-modal`). I executed both against
hooks/lib/pane-modal.sh: anchored → 1, unanchored → 0/mcp-trust-modal. The override is set as a
plain shell var, and if bats' `run` did not carry it the control would go RED, not silently green —
breakage direction is correct. Same for L176's replacement half: if the override failed to
propagate, `mcp_screen` would classify 0 and the `-eq 1` assertion reds.

3) Every assertion's subject is its own input, and no count is asserted anywhere.
Scored classes "span exceeds subject" and "exact-count reds on growth" have no surface here: there
is no `grep -c`, no `wc`, no `-eq N` over a population — the only `-eq` are on `$status` and on an
exact slug string, where the value set is `{0,1}` / `{mcp-trust-modal, workspace-trust-modal}` and
`-ge` would be meaningless. I executed all 13 classify inputs plus both override cases; every
asserted status/output matches the real lib (positives 1,2,6,7,14,15 → 0; negatives 3,4,5,8,9,10,11,
12,13,16 → 1). The conjunction arms are mutation-live, not decorative: L137 (header, no option) reds
under a header-only rule, L146 (option list, no header) reds under an option-only rule, L155 (MCP
header + TRUST option) reds if the conjunction were flattened across classes.

4) Shell-shape audit and negative/positive pairing.
No `[[ ]]`, no `(( ))`, no `! cmd`, no `[ A ] && [ B ]` anywhere in the assertions — every one is
`[ ... ] || false`. The two `X && { ...; return 0; }` forms are inside `claude_binary` (L222, L236),
each followed by a reachable `return 1`; an AND-list whose left side fails does not trip errexit, so
the fallthrough is real, not swallowed. Every negative arm has a positive: MCP negatives ↔ L70/L110,
trust negative (L132) ↔ L76, the mutant-absent control (L264) ↔ the fragments-present arm (L248).
The two arms I pushed hardest on for over-claim both survive: "an unreadable pane fails CLOSED …
never to wedged" (L169) is a one-sample universal, but the production shape of an unreadable pane IS
an empty capture (the consumers pass plain `get-text` output), and the assertion is falsifiable — an
empty or everything-matching pattern makes the empty line classify as a modal; and "every slug
carries a remedy" (L188) is structurally guaranteed by the `*)` arm rather than over-claimed, while
the `grep -q enabledMcpjsonServers` assertion proves the specific arm has not collapsed into that
default. Neither title asserts something the body cannot measure.

OPEN_FINDINGS: none found; searched docs/plans/, docs/research/, docs/rulings/, docs/proposals/ and
a repo-wide grep for `pane-modal` / `pane_modal` / `mcp-trust-modal` (excluding .git, node_modules).
The only doc reference is docs/plans/TERMINAL_AGNOSTIC_L3_L4.md §9.6 (L1231, L1274), which records
this suite as landed verification — 17 tests (I counted exactly 17 `@test` blocks), 11 mutants
convicted, with the one surviving mutant explicitly attributed to a different file
(handoff-fire.sh's pre-resend abstain, since pinned). `git log -- tests/pane-modal.bats` shows a
single commit, 399ed0da, with no follow-up or revert. Also checked
docs/research/BATS_DEAD_ASSERTIONS_2026-07-25.md and GATE_RELIABILITY_2026-07-25.md — neither names
this file.
