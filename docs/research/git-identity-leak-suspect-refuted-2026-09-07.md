# The 2026-09-04 identity leak: the named suspect is refuted, and so is the obvious exoneration

Backlog `23255fbb8792` — *"the shared .git/config carried a [user] section (email t@t, name t)
again on 2026-09-04 ~17:20Z … tests/git-identity-lint.bats:297-307 probe shape is the prime
suspect … make the corpus unable to write the real repo config."*

Two things a successor would otherwise re-derive. Neither closes the row.

## 1. The named suspect cannot be the culprit

`tests/git-identity-lint.bats` never EXECUTES an identity write. Every `git -C … config
user.email` token in it — lines 63, 76, 90, 101, 112, 123, 149, 172, 182, 195, 208, 214, 227,
241, 283 and the `probe=` shapes at 297-307 — is payload TEXT, written through the file's own
`fixture()` helper into `$FIX/<name>/tests/probe.bats` and then passed to the lint as a scan
root. The lint reads those files; nothing runs them.

    fixture() { mkdir -p "$FIX/$1/tests"; cat > "$FIX/$1/tests/probe.bats"; echo "$FIX/$1"; }

So the "failed cd leaves the write in the real repo" mechanism the row names has no site here:
there is no cd and no execution. The suspect is refuted by reading the file.

## 2. …but the corpus-wide ratchet being CLEAN does not exonerate the corpus either

`scripts/git-identity-lint.sh` reports, on this tree:

    git-identity-lint: clean — 882 file(s); 0 grandfathered, 0 escaping identity writes.

Its population is `tests/*.bats` + `scripts/*.sh` + `bin/*`, so `bin/` is covered (the sites in
`bin/cc-value`, `bin/cc-teardown`, `bin/cc-respawn`, `bin/cc-dispatch:3794` are all judged and
all green — `cc-dispatch`'s `cd "$wtrepo"` is bound at `wtrepo="$tmp/wtrepo"`, a literal suffix,
which is the lint's own "PROVEN non-emptiable" rung).

**That verdict is not a cure, because it was already true when the leak happened.** The ratchet
landed 2026-08-16 (`c037c1aa1` … `41f2d21be`), was last touched 2026-08-26 (`80294d709`), and is
wired into the land gate at `scripts/ship-land.sh:2947`. All of that predates 2026-09-04T17:20Z.
A live, clean, land-blocking ratchet did not stop the write, so the escape path is OUTSIDE its
model — and closing the row on "the lint is clean" would be laundering.

## Where to look next

The ratchet's model is *"the write must land inside the fixture"*, and it judges one file at a
time. Two shapes defeat that by construction and are unscanned by it:

* **A linked worktree of the REAL repo used as a fixture.** A linked worktree shares
  `.git/config` with the checkout, so an identity write inside one is a direct hit even though
  every `cd` is guarded and every path is proven. `tests/cc-backlog.bats:2060` creates exactly
  such a worktree (`git -C "$REPO" worktree add --detach "$wt" HEAD`, `$REPO` = the real
  checkout); it writes no identity itself, but it establishes that the shape is in the corpus.
* **A cross-file pairing.** The `cd` in the test and the write in the script it invokes live in
  different files, so rule 2's same-region pairing never sees them together.

Either would explain a leak the ratchet reports as clean. Neither is proven here.
