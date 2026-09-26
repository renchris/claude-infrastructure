# Post-land AUTO-REVERT FAILED (step=land rc=124) for `tests/agents-omit-claudemd.bats` @ 2be051f3: moot, the revert and the corrected re-land are both on trunk

cc-backlog `8196a5270ab2`. Verdict: **CURED ON TRUNK. Nothing to land.** The automatic revert's land
timed out (rc 124), but the same revert reached trunk as `e7321f2a`. The real fixes that revert took
back out were then re-landed green as `351d910e`.

## Cure shas (both asserted against origin/main)

    $ git merge-base --is-ancestor e7321f2a8eb42c2c9a58cf2b96afc3f00da269f9 origin/main && echo revert-on-trunk
    revert-on-trunk
    $ git merge-base --is-ancestor 351d910e origin/main && echo reland-on-trunk
    reland-on-trunk

- `e7321f2a` is `Revert "fix(agents): point research agents at the research-subagents skill, and
  quote the critic's description"`. It is the exact revert this row's auto-revert was trying to
  land from `postland-revert-2be051f3ade1`. That branch no longer exists on the remote.
- `ab51026d` is the sibling verdict for the RED itself (cc-backlog `0ef0c3577a86`, file
  `docs/research/agents-omit-claudemd-red-2026-09-26.md`).
- `351d910e` re-lands `2be051f3`'s two real fixes without growing the critic's description:
  - the six research-subagents references now point at the skill;
  - the critic's frontmatter is valid YAML.

## What I ran (off-box cloud VM, unshallowed, `HEAD..origin/main` = 0, tip `351d910e`)

bats-core was cloned fresh, because the VM has no bats on PATH:

    $ bats tests/agents-omit-claudemd.bats
    1..3
    ok 1 1: the four research subagents declare omitClaudeMd: true in their frontmatter
    ok 2 2: every omitClaudeMd agent that can write carries the operating contract
    ok 3 3: the adoption did not grow the agent descriptions every session loads

Checks on the residual that the sibling verdict flagged:

- `yaml.safe_load` of `agents/research-decomposition-critic.md`'s frontmatter prints `critic yaml ok`.
- `grep -rn 'rules/research-subagents' agents/` finds 0 matches.

The residual is therefore closed as well.

## Dispatcher vintage

The brief's blob `dc9130372d6332940388c2a17da7c65c1af3c3bd` equals `origin/main:bin/cc-dispatch`. The
dispatcher that fired this row IS the trunk version.

## Not established from here

I did not determine why the auto-revert's land hit rc 124. The row's payload is the revert, and it
is on trunk, so that timeout carries no work that is still owed. Whatever bounded the auto-revert
lander (ship-land under lock contention, see `docs/lessons/never-wrap-ship-in-your-own-timeout.md`)
is a separate question about the lander, and it is not reproducible off-box.
