# The bash-3.2 ratchet went standing-red on a prose apostrophe — and the ratchet is not a gate arm

Row: cc-backlog `6ad987e258f7` — post-land RED,
`tests/bash32-parse-lint.bats::the tree as it stands is CLEAN — a ratchet that ships standing-red is rot`,
cited at `4592195b4e23`. Worked off-box (cloud VM), 2026-09-11.

Cure: `hooks/recover-inject.sh` — the emitted notice moved out of
`BODY="$(cat <<EOF … EOF)"` and into the house idiom `IFS= read -r -d '' BODY <<EOF || true`.

## 1 · Trunk reads first, because a post-land RED reproduces faithfully in a stale tree

| read | result |
|---|---|
| `git rev-parse --is-shallow-repository` | `true` → `git fetch --unshallow` before any trunk read |
| `git rev-list --count HEAD..origin/main` | **0** — this tree *is* trunk |
| `git merge-base --is-ancestor 4592195b4e23 origin/main` | yes |
| `git rev-parse origin/main:bin/cc-dispatch` | `27c461a5f1a4de551fdfbe2a619e28e696c13aaa` — **EQUAL** to the blob that composed the brief, so the dispatcher that fired this row IS trunk |

No cure for this red was on trunk: the tree was still red when this work started.

## 2 · The cited sha is not the culprit, and its own diff says so

`4592195b` is `docs(rules): an allow rule cannot silence a hook's ask` — a documentation commit.
`bash32-parse-lint.sh` scans **every tracked file with a bash/sh shebang**, so it is a whole-tree
ratchet: it is reached by every commit, and reachability therefore carries no attribution
information for it (corpus rule: *a ratchet's culprit is in its output, not in the range*). The
culprit landed earlier and this commit is merely where postland happened to look.

The load-bearing fact is the opposite one: the lint landed **green** at `ec3f7c0f` ("554 scripts
scanned, this was the only instance"). So the culprit is a population member that changed between
`ec3f7c0f` and `4592195b` — 33 files, of which 4 were new.

## 3 · The instrument, because there is no bash 3.2 off-box

This VM is Linux with `/bin/bash` 5.2. `tests/bash32-parse-lint.bats` therefore **SKIPs all 7
cases** by its own declared precondition, and `scripts/bash32-parse-lint.sh` exits 2 (NON-VERDICT).
Building a real bash 3.2 was attempted and is not possible here: `ftp.gnu.org`, `mirrors.kernel.org`
and `cdn.jsdelivr.net` are all refused by the egress proxy, and GitHub access is scoped to this one
repository, so `bminor/bash` is unreachable.

What was built instead is a **matched-pair differential**, not a bash parser. bash 3.2's
`parse_matched_pair()` hunts for the `)` that closes a `$( )` **without honouring a heredoc
delimiter** — it lexes the heredoc body as shell code. So: locate every command substitution with a
heredoc-AWARE walk (what bash 4+ does), then re-find the same closer with a heredoc-BLIND walk (what
bash 3.2 does), and report every substitution where the two land in different places.

It is controlled on four arms before it is believed, two of them the repo's own ground truth:

| arm | expected | got |
|---|---|---|
| pre-fix `scripts/mcp-ssot-wire.sh`, blob `949ff9bd` (the real artifact) | CAUGHT | CAUGHT — 3.2 overshoots the real closer at line 271 and lands at 286 |
| the cured twin on trunk | CLEAN | CLEAN |
| the scar fixture from `tests/bash32-parse-lint.bats::_write_scar` | CAUGHT | CAUGHT |
| the same fixture with the apostrophe removed (one variable) | CLEAN | CLEAN |

The first arm corroborates the mechanism independently: `ec3f7c0f`'s commit message records the real
bash 3.2 error as `line 288: syntax error near unexpected token 'fi'`, and the differential puts the
misplaced closer at line 286 — two lines above it.

Two bugs in the instrument were found by these arms and by the population sweep, and both are worth
naming because each reads as a clean answer:

* the heredoc-aware walk did not count **plain `( )` subshell nesting**, so it returned the inner
  `)` of `$( ( cd … ) 2>&1 )` and manufactured 27 false divergences;
* a here-**string** `<<<"$x"` was re-read as a heredoc on its second `<`, taking `$x` as the
  delimiter and swallowing the rest of the file as a heredoc body — which silently hid the real
  culprit, because the walk desynced 60 lines above it and never saw its `$(`. A scanner that has
  eaten the rest of the file reports **clean**.

## 4 · The A/B, and the culprit

Same instrument, same population rule, two trees:

```
A  ec3f7c0f  (lint landed GREEN here)   scanned=556  divergent=2
     hooks/lib/is-true-flag.sh: $( line 50  → real closer 202, bash 3.2 lands at 65
     hooks/lib/is-true-flag.sh: $( line 264 → real closer 415, bash 3.2 lands at 320

B  origin/main (post-land RED)          scanned=560  divergent=3
     hooks/lib/is-true-flag.sh: $( line 50  → real closer 202, bash 3.2 lands at 65
     hooks/lib/is-true-flag.sh: $( line 264 → real closer 415, bash 3.2 lands at 320
  ✗  hooks/recover-inject.sh:   $( line 155 → real closer 190, bash 3.2 lands at EOF
```

Exactly one new divergence, in a file **added** since the green run. The two `is-true-flag.sh` rows
are byte-identical in both trees (that file has 0 commits in the range) and the lint was GREEN over
them, which is the measured proof that **a matched-pair divergence is not by itself a parse error** —
3.2 lands on a different `)` there and the remainder still parses. They are not this row's finding
and were not touched.

`hooks/recover-inject.sh:155` is `BODY="$(cat <<EOF`. Its heredoc body is 38 lines of English prose,
and line 179 reads:

```
  2. Disk silence is NOT death. Read the audit's 'lead process' line: a network drop usually leaves
```

Three apostrophes on one line, and the only three in the body. To bash 3.2 the first opens a quote
and the second closes it; the third opens one that never closes — it swallows lines 180-191 **including
the real `)` on line 191** — and the scan runs to EOF. Same class, same mechanism and same shape as
the `mcp-ssot-wire.sh` scar the ratchet was built for; only the spelling differs.

### The other 3.2-fatal classes were swept too, and found nothing new

The differential only covers heredoc-in-`$( )`. A second sweep blanks comments, quoted strings and
heredoc bodies, then looks in the remaining code skeleton for syntax bash 3.2's parser rejects and
bash 4+ accepts: `;;&`, `;&`, `|&`, `&>>`, `coproc`. Positive-controlled on a planted `;;&`
(found) beside the same token in a string and in a comment (both correctly silent).

Trunk: 1 hit, `hooks/validate-bash.sh:1450` — a Python string `PUNCT = "();<>|&\n"` inside a
heredoc, i.e. a false positive of the skeleton extractor. It is present in the **green** tree too
(at line 1266, before the range shifted it). No new bash-4-only syntax landed in the range.

## 5 · The fix, and why it removes the construct rather than the apostrophes

`ec3f7c0f` cured `mcp-ssot-wire.sh` by rewording, because that heredoc body is a Python program
whose comments can be written to a rule. This body is **prose written for a model to read**, and a
later editor will keep growing apostrophes in it. A no-apostrophes rule over English prose is a
standing trap, so the construct goes instead — `scripts/git-identity-lint.sh:182` already documents
the idiom and this exact rationale for the same reason:

> `read -r -d ''`, NOT `$(cat <<'AWK' … AWK)`. This box's /bin/bash is 3.2, whose `$( )` parser
> counts parentheses across the heredoc body before the heredoc is honoured …

The heredoc keeps an **unquoted** `EOF`, because this body interpolates `$HEAD`, `$DETAIL`, `$POP`,
`$OPEN_LINES` and carries `\\` and `\$` escapes. Expansion semantics are identical between the two
constructs; the only difference is that `$( )` strips trailing newlines and `read` does not, so one
`BODY="${BODY%$'\n'}"` makes the emitted bytes identical.

Measured, one variable, the same construct with the same inputs both ways: the two `od -c` dumps
differ in exactly one trailing `\n`, which the strip removes. The heredoc TEXT is byte-identical
between trunk and the fix (`diff` of the extracted block: identical) — no prose changed.

## 6 · What was verified here, and what could not be

Run on this VM, on the fixed tree:

* the differential: `hooks/recover-inject.sh` CLEAN; the population's only remaining rows are the
  two pre-existing `is-true-flag.sh` divergences that were green at `ec3f7c0f`;
* the skeleton sweep: no new 3.2-fatal syntax;
* `bash -n hooks/recover-inject.sh` — OK (the control arm the lint itself requires: a reported file
  must parse under a modern bash);
* `shellcheck 0.11.0` — rc 0 on the changed file, and rc 0 on its trunk baseline (no new finding);
* `bats tests/recover-inject.bats` — **18 ok / 0 not ok**, plan line `1..18` present. Every
  assertion in that suite is a substring test on `additionalContext`, so the construct swap is
  behaviour-preserving by the suite's own predicate as well as by the byte diff;
* twelve of the repo's lint arms run A/B against a pristine `origin/main` worktree — identical exit
  codes and no new findings in every one; the four that differ textually differ only in per-file
  memo lines and in the worktree path they print.

**Not verifiable off-box, and this is the honest limit of this record:** the ratchet itself.
`tests/bash32-parse-lint.bats` SKIPs all 7 cases here (`no bash 3.x at /bin/bash — this ratchet's
precondition is environment-falsifiable`), and the lint returns NON-VERDICT (exit 2) rather than a
green. The differential above is an emulator validated against the repo's own artifact, not the
instrument the ratchet uses. The single command that settles it, on the desk:

```
bats tests/bash32-parse-lint.bats        # case 1 must be `ok`, not `skip`
bash scripts/bash32-parse-lint.sh        # must print "… script(s) parse under bash 3 — clean"
```

## 7 · The finding this row did not ask for: the ratchet is not a gate arm

`scripts/bash32-parse-lint.sh` appears nowhere in `scripts/ship-land.sh`. `run_gate` names eighteen
lint arms that run on every land outside selection (`HERM_LINT`, `WALL_LINT`, `AFUNIX_LINT`,
`MOVINGREF_LINT`, `GITID_LINT`, `UTC_LINT`, `PF_LINT`, `SELFPATH_LINT`, `PSPAWN_LINT`,
`UNATTENDED_LINT`, `PERMGATE_LINT`, `CHROMIUM_LINT`, `TSVPAD_LINT`, `SC_BATS_LINT`,
`KILL_GUARD_LINT`, `TESTNAME_LINT`, `LOADED_LINT`, `ADM_LINT`) — and this ratchet is not among them.
Its only reachable surface is `tests/bash32-parse-lint.bats`, and ship-land's own header records
that selection maps a new `tests/*.bats` to itself and never to a ratchet
(`scripts/ship-land.sh:182`). So adding `hooks/recover-inject.sh` selected nothing that could see
it, the file landed, and the ratchet has been standing-red ever since — which is precisely the state
the failing case is named after.

This is the mechanism by which the class recurs, and it is **not fixed here**. Wiring a nineteenth
arm into `run_gate` cannot be verified from this VM (the gate is macOS-shaped, `tests/ship-land.bats`
asserts on the arm set, and `ship-land.sh` is the most contended file in the tree), so it is recorded
rather than attempted — a one-line change made blind to the gate it changes is worse than the red it
closes. The residual is: **either make `bash32-parse-lint.sh` a `run_gate` arm, or give it an
`own`-set entry so that any population member selects it.** Until one of those, the next apostrophe
in a heredoc inside `$( )` lands exactly the same way.
