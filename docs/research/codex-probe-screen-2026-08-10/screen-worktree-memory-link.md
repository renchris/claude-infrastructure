VERDICT: DEFECTIVE

EVIDENCE:

1. Line 51 (with the claim at lines 44-50) — `encode() { printf '%s' "$1" | sed 's|[/.]|-|g'; }`
   The guard enumerates two SPELLINGS (`/` and `.`) of the class it names ("Claude Code's
   project-dir encoding"), and the real class is wider: every non-alphanumeric char becomes `-`,
   including `_`. Ground truth on this same box, same method the header claims to have used
   (the `cwd` field inside session transcripts):
     cwd  /Users/chrisren/Development/doc_classifier
     dir  ~/.claude/projects/-Users-chrisren-Development-doc-classifier   (13 sessions, all agree)
   `encode()` yields `-Users-chrisren-Development-doc_classifier`. Zero of the 354 project dirs on
   this box contain `_`, while at least one real cwd does — so the underscore rule is Claude Code's,
   not a coincidence. The header's "Verified 2026-07-31 against ground truth … not inferred" is a
   success/verdict token for a check whose span was narrower than its subject: it verified two
   characters and certified the encoding.

2. Line 97 (consequence of 1, primary side) — `[ -d "$pmem" ] || continue`
   For any repo whose path holds `_` (or any other non-alphanumeric outside `/.`), `$pkey` names a
   project dir that by construction cannot exist, so the lookup misses and the miss is read as
   "primary has no memory here — nothing to share". The script then silently does nothing, exits 0,
   and logs nothing, on exactly the case it exists to fix.

3. Lines 117-121 (consequence of 1, worktree side) — `mkdir -p "$cfg/projects/$wkey"` … `ln -s "$rel" "$wmem"` … `log "linked $wmem -> $rel"`
   If only the WORKTREE path holds `_`, `$pmem` resolves, so the script mints a project dir and a
   valid-looking symlink at a key no session will ever use, prints the success token `linked …`,
   and counts it in `n`. The certified quantity (a link exists) is not the claimed one (the next
   session in that worktree resolves memory). Nothing downstream ever measures the latter.
   This is worse than a no-op: it feeds the unbounded-cardinality problem the comment at 109-114
   is explicitly trying to avoid, with dirs that are pure residue.

4. Line 33 of tests/worktree-memory-link.bats — `PKEY="$(printf '%s' "$REPO" | sed 's|[/.]|-|g')"`
   The suite recomputes the key with the SAME lossy rule instead of an independent oracle, so the
   defect is unfalsifiable by the tests: any encoding divergence moves the assertion and the
   subject together and the suite still greens. (The setup comment at 20-25 shows the authors
   already got burned once by asserting on a slot the script never touched.)

5. Line 134 vs line 137 — comment says `--all-create opts into minting project dirs`; the code
   implements `--all --create` (`[ "${1:-}" = "--create" ]`). Neither spelling appears in the Usage
   block at lines 32-35. Invoking the documented flag falls through `[ "${1:-}" = "--create" ]`,
   is taken as the `target` path at line 138, fails `primary_of`, and exits 0 with
   "not a git repo: --all-create" — a silent wrong-mode run.

6. Line 142 — `awk '/^worktree /{print $2}'`
   `$2` truncates at the first space, so `--all` over a repo whose worktrees sit under a path with
   a space feeds `link_one` a truncated path, which fails `cd` and is swallowed as
   "skip (unreadable)". Same enumerate-the-easy-case shape as (1); lower severity because
   `.worktrees` trees here are machine-named.

Not defects (probed and cleared): `set -uo pipefail` with no `-e` means the `[ A ] && [ B ]`
one-liners at 59/100/116/125 cannot and-absorb a failure into an early exit, and every path
returns/exits 0 as the fail-soft contract at 26-30 requires; the relative link `../$pkey/memory`
at 120 is correct from the link's own directory `$cfg/projects/$wkey`; line 100's dangling/aim
check correctly falls through to repoint because `-d` follows the symlink.

OPEN_FINDINGS: none found; searched all of docs/ (research + plans) and the whole repo excluding
.git for `worktree-memory-link` / `memory-link` / `memory_link`. The only hit is
/Users/chrisren/Development/.worktrees/probe-corpus/docs/research/git-identity-leak-2026-08-05.md:157,
which names tests/worktree-memory-link.bats:19 only to mark its transient `git -c user.email=` as
SAFE by construction — no finding against scripts/worktree-memory-link.sh.
