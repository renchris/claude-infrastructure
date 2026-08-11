VERDICT: DEFECTIVE

EVIDENCE:

1. PRIMARY — memo keyed on something that does not capture what invalidates it: the salt omits
   `.shellcheckrc`, which decides shellcheck's verdict.
   File: /Users/chrisren/Development/.worktrees/probe-corpus/scripts/lib/gate-memo.sh
   Lines 93-99 (the salt) and 149 (the key):

     MEMO_SALT="$(
       printf 'gate-memo/v1\n'
       printf 'shellcheck=%s\n' "$(shellcheck --version 2>/dev/null | awk '/^version:/{print $2}' || true)"
       ...
     printf '%s\nchecker=%s\nblob=%s\n' "$MEMO_SALT" "$1" "$blob" | _memo_hash

   The key is (versions of shellcheck/bash/python3/git) x (checker-id) x (this file's blob).
   shellcheck's verdict is ALSO a function of repo-root `.shellcheckrc`, which this repo ships and
   which is live policy (`disable=SC2001,SC2015`, committed d30f9899, self-described as "a FLOOR",
   i.e. expected to be tightened). Nothing in gate-memo.sh, ship-land.sh, or anywhere in the tree
   reads or hashes `.shellcheckrc` (`git grep -n shellcheckrc origin/main` hits only docs/plans).
   The gate invokes `shellcheck "${sc_todo[@]}"` with no flags and no `--norc` (ship-land.sh:1664),
   so the rc file is in force.

   EXECUTED, at repo root, shellcheck 0.11.0:
     printf '#!/usr/bin/env bash\nx=a\necho "$x" | sed "s/a/b/"\n' | shellcheck -        -> rc=0
     printf '#!/usr/bin/env bash\nx=a\necho "$x" | sed "s/a/b/"\n' | shellcheck --norc - -> rc=1 (SC2001)
   Same bytes, same shellcheck version, opposite verdict. The rc file alone flips green to red.

   Why it fires, in this file's own motivating scenario: round 1 of a land proves foo.sh green and
   records it; a SIBLING lands mid-gate (exit 42) and its delta tightens `.shellcheckrc`; we rebase
   and re-round. foo.sh's blob is unchanged, so `memo_file_hit` carries the round-1 green and foo.sh
   is never handed to shellcheck under the new policy — a red lands green. The store
   (<git-common-dir>/ship-land-memo/) is never pruned or version-stamped (no writer other than
   _memo_put anywhere in the tree), so every entry ever earned under a looser rc stays honourable
   indefinitely, and it is shared by every worktree of the repo (line 78), widening the window
   further. This is precisely the "stale-verdict generator" the file's own line 84 names as "the one
   failure mode worse than the cost it saves", and it breaks the stated invariant at line 23
   ("a green it has already EARNED, for exactly the inputs it earned it on") — the rc file is an
   input to that verdict. The completeness claim at lines 85-86 ("Every interpreter that decides a
   memoized verdict is in here") is therefore false: configuration decides it too.
   Fix shape: fold `git hash-object .shellcheckrc` (or its content, and absence-as-empty) into
   MEMO_SALT alongside the version strings. Note `bash -n` and py_compile are genuinely pure and are
   correctly covered by the interpreter versions — the gap is shellcheck-specific.

2. SECONDARY (comment, not behaviour) — the load-bearing rationale for the dirty-tree guard
   describes a mechanism that is not in the file.
   Lines 46-47: "Per arm it is: one `git ls-tree` over the arm's population and one
   `git hash-object --stdin`"; lines 66-72: "The population fingerprint below is computed with
   `git ls-tree HEAD` — the COMMITTED tree ... asserting it here anyway means ... can never silently
   turn `ls-tree` into a stale-verdict generator."
   There is no `ls-tree` in the executable body (grep: `ls-tree` appears only at lines 46, 67, 72,
   all comments). The implementation is `git hash-object -- "$2"` on the on-disk file (line 147), and
   line 145 says so explicitly and in contradiction to line 67. The guard at line 73 is harmless
   (its only effect is to disable the memo more often, the safe direction), but a reviewer relying on
   the stated reason would be reasoning about the wrong code.

WHAT I PROBED AND CLEARED (so the conviction is attributable):
   - `set -e` and-absorption: lines 64, 73, 160 are `[[ A ]] && return 1` shapes that would exit
     under `set -e`. ship-land.sh:138-139 is `set -uo pipefail` with an explicit "NO `set -e`", and
     the lib is only sourced from there (and from tests/land-gate-memo.bats). Not a defect here.
     Under `set -u` every variable the lib reads is initialised at source time (lines 55-59) and
     `${SHIP_LAND_MEMO:-on}` is guarded. Under `pipefail`, both salt pipelines carry `|| true`.
   - Fail direction / vacuous pass: `_memo_get` (line 121) is an exact whole-body literal match with
     the digest restated inside, only rc 0 is ever recorded, and every failure path (memo off, no
     key, unreadable, corrupt) returns non-zero, which memo_partition (line 170) turns into "print
     the path" i.e. run the check. The lookup-miss-as-absence hazard is inverted correctly: a miss
     means MORE work, never a green. Verified against the /Users/chrisren/.claude/bin/cc-bats corruption/unreadable/red tests.
   - Subsetting soundness: shellcheck is called without `-x`, so per-file verdicts compose; recording
     happens only on a whole-set green (ship-land.sh:1664-1668), so a red records nothing.
   - `shellcheck -s bash` on the file itself: rc=0, no findings.

OPEN_FINDINGS: none found. Searched `grep -rn gate-memo docs/` and
`grep -rniE 'gate-memo|statics memo' docs/ | grep -iE 'open|defect|bug|unsound|stale|finding'`, plus
`git grep -n 'gate-memo\|SHIP_LAND_MEMO' origin/main`. The only doc reference is
docs/research/land-architecture-100p-2026-08-10.md:601,613-618, which records P3 as shipped and
sound; it does not name the `.shellcheckrc` gap.
