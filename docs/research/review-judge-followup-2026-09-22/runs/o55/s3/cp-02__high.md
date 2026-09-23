# Review of `tests/activation-watch.bats`

I found seven defects. Line numbers count from the shebang as line 1.

---

### 1. The LIVE-ONLY test's name assertion is satisfied by axis 1, not axis 2

- **What:** The fixture is not `.done`-marked, even though the section header says it is. So the file-name assertion passes on axis 1's FRESH listing, not on the parity finding.
- **Where:** line 91: `  stage "12-only-live-activate.sh"` (asserted at line 94: `  printf '%s' "$output" | grep -q '12-only-live-activate.sh'`)
- **Why it is wrong:**
  - Since M3, axis 1 names every un-run script under FRESH. That means `12-only-live-activate.sh` is always in the output.
  - Line 94 therefore passes even if the LIVE-ONLY row names nothing, or names the wrong file.
  - Line 95 only checks that the word `LIVE-ONLY` appears somewhere.
  - The headline claim, that a live-only file is *named* as LIVE-ONLY, is never proven.

### 2. The CONTENT-DRIFT test has the same flaw

- **What:** The drift fixture is written without a `.done` marker, so the file-name grep is satisfied by axis 1's FRESH partition.
- **Where:** line 109: `  printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"` (asserted at line 112: `  printf '%s' "$output" | grep -q '07-drift-activate.sh'`)
- **Why it is wrong:**
  - The un-marked live file is always listed by axis 1.
  - Line 112 passes whether or not the CONTENT-DRIFT row names it.
  - Only the bare keyword on line 113 depends on axis 2.

### 3. The symlink test cannot reproduce the failure it guards against

- **What:** The symlink is created in `$BATS_TEST_TMPDIR`, not under `~/.claude`. A hook that fails to dereference it can never produce a `.claude/docs/activation` path, so the negative check can never fail.
- **Where:**
  - line 145: `  ln -s "$H" "$BATS_TEST_TMPDIR/linked.sh"`
  - line 150: `  ! printf '%s' "$output" | grep -q '\.claude/docs/activation'`
- **Why it is wrong:**
  - With a broken dereference, `BASH_SOURCE` resolves to a path under the temp dir, not `~/.claude`. Line 150 therefore passes regardless.
  - That temp path has no `.git`, so the gate falls through to FALLBACK_REPO.
  - When the suite is run from the shared checkout (FALLBACK_REPO equals `$REPO`), line 149 also passes.
  - The comment "not the FALLBACK_REPO shared checkout" is unverified. A regression in the dereference would pass this test.

### 4. The M4 fixtures build a checkout that is ahead of trunk, not behind it

- **What:** The fixtures never create the "behind trunk" shape they claim to model.
- **Where:**
  - lines 235–237: `  ( cd "$w"; git rm -q docs/activation/pending-activation/landed-activate.sh; git commit -q -m drop` / `    git reset -q --hard HEAD~1; ...` / `    rm -f ...; git commit -q -m "checkout behind" ) >/dev/null 2>&1`
  - The same shape appears at lines 270–271.
- **Why it is wrong:**
  - The "drop" commit is never pushed, and `reset --hard HEAD~1` undoes it. That step is a no-op.
  - The final commit makes local `main` one commit **ahead** of `origin/main`, with `landed-activate.sh` still in HEAD's own history (the `base` commit).
  - An adjudicator that asks "was this path ever committed in HEAD's history" would report UNDEPLOYED-MIRROR here and pass. The same adjudicator would report LIVE-ONLY in the real deploy-lag case, where the file exists only in upstream commits the checkout lacks.
  - The test does not cover the class the comment says it covers.

### 5. The M4 negative check is pinned to an exact string that nothing proves is ever emitted

- **What:** The check that the file is not reported as never-committed matches one verbatim phrasing. Neither this test nor its positive control shows that phrasing exists in the output.
- **Where:** line 242: `  ! printf '%s' "$output" | grep -q "LIVE-ONLY — never committed, one .rm. from unrecoverable: landed-activate.sh" || false`
- **Why it is wrong:**
  - The positive control (lines 253–254) only greps `LIVE-ONLY` and the file name as separate matches.
  - If the real row uses different punctuation or wording, or lists several files on one line (`...: other.sh, landed-activate.sh`), line 242 passes even when `landed-activate.sh` *is* misreported as LIVE-ONLY.
  - That misreport is exactly the damaging verdict this test exists to forbid.

### 6. The M4 test subshells run destructive git commands without checking that `cd` succeeded

- **What:** Unlike `mkmirror` (`cd "$w" || exit 1`), these subshells run `git commit` and `git reset --hard` after a `cd` that is never checked.
- **Where:**
  - line 235: `  ( cd "$w"; git rm -q docs/activation/pending-activation/landed-activate.sh; git commit -q -m drop`
  - line 236: `    git reset -q --hard HEAD~1; git rm -q --cached docs/activation/pending-activation/landed-activate.sh`
  - line 270: `  ( cd "$w"; git rm -q --cached docs/activation/pending-activation/landed-activate.sh`
- **Why it is wrong:**
  - `mkmirror` always prints `$w`, even when the init or clone failed.
  - If `$w` does not exist, `cd` fails and the commands run in bats' working directory, usually the real repository checkout.
  - There, `git commit` commits whatever is already staged, and `git reset --hard HEAD~1` discards that commit plus all uncommitted work.
  - All output goes to `/dev/null`, so none of this is visible.

### 7. The M5 kill-switch test is purely negative and passes if axis 3 never runs

- **What:** The only assertion is that `CLAIMED-DONE BUT INERT` is absent. Nothing shows the restored com.claude-only pattern is still active, or that the hook even succeeded.
- **Where:** line 327: `  ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false`
- **Why it is wrong:**
  - The test would pass if `CC_ACTIVATION_INERT_SCOPE=claude` switched axis 3 off entirely, matched nothing at all, or made the hook crash with empty output.
  - `$status` is not checked, and there is no com.claude label fixture that should still fire.
  - "Restores the com.claude-only pattern" is therefore never verified; only "emits no INERT row" is.
