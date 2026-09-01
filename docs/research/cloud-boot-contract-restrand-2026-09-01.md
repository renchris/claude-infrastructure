# The boot contract was built four times. None of the four reached trunk.

**2026-09-01 · verdict artifact for backlog `0c8b39b67665`, written from the cloud VM it was
dispatched into (5th dispatch).** Everything below was read on TRUNK
(`git rev-list --count HEAD..origin/main` = 0 at the time of reading), never recalled.

**Verdict in one line:** the row's premise — *"CLOUD_OBSERVABILITY.md's 'first act = push an empty
commit' contract is PROSE-ONLY, never implemented"* — is **TRUE on trunk and FALSE about the
fleet.** Four prior dispatches each built it, each pushed it, and none of the four landed; the row
stayed `open` and was dispatched a fifth time. The condition this row describes is not an unbuilt
feature. It is a **land-arm casualty that reads as an unbuilt feature**, and every re-dispatch
re-derives the same diagnosis at full cost.

---

## 1 · The premise holds on trunk — verified by content

`origin/main` at `06f96e4d` (read 2026-09-01). §4.1 of `docs/plans/CLOUD_OBSERVABILITY.md` states
the contract at line 149 and it exists nowhere else:

```
$ grep -rn 'BOOT BEACON\|--allow-empty' bin/cc-offload scripts/lib/cloud-create.sh \
      scripts/handoff-fire.sh
(no match — the only --allow-empty in bin/cc-cloud:1144 is a test fixture's seed commit)
```

Both lanes were measured, not inferred:

| Lane | What the VM was actually told, on trunk | Verdict |
| --- | --- | --- |
| **API** — `cc-offload up --via api`, what `cc-dispatch` fires | `cc-notify --cloud "$sid" "$(cat "$pf")"` — the composed brief **verbatim**, no return instruction of any kind (`bin/cc-offload:581` pre-change) | no beacon, no push instruction at all |
| **CLI** — `handoff-fire.sh --cloud` | a `HOW TO RETURN YOUR WORK … read this before you finish` trailer: `git switch -c <br>; git push -u origin HEAD`, plus *"Push whatever you have before you finish"* | a **return** push — the last act, not the first |

So `no ref` still conflated §4.1's four worlds, and `C1 NOT-STARTED` reported *"has not pushed
yet"* — which every healthy worker satisfies for most of its life — while rendering as *"nobody
ever booted; re-fire or check entitlement"*.

## 2 · …and it had been built four times, on four branches that never landed

`git log --all --follow -- docs/plans/CLOUD_OBSERVABILITY.md`. None of these four shas is an
ancestor of `origin/main` (`git merge-base --is-ancestor <sha> origin/main` → rc 1 for each), and
none of the work is on trunk by any other route — `git grep 'BOOT BEACON' origin/main` returns
nothing:

| sha | date | branch | lanes covered |
| --- | --- | --- | --- |
| `0b9920cb` | 2026-08-29 10:15 | `claude/fire-20260829T094954Z-2459-1` | `bin/cc-cloud` + both fire lanes, +497/−15 |
| `b3bd322e` | 2026-08-29 20:56 | `claude/fire-20260829T202939Z-12357-1` | shared library + both lanes, +288/−14 |
| `a1b37ac2` | 2026-08-31 01:26 | `claude/fire-20260831T010522Z-29561-1` | shared library + both lanes, +349/−3 |
| `faf78977` | 2026-08-31 20:38 | `claude/fire-20260831T201554Z-59973-1` | shared library + both lanes, +335/−36, **verified live from inside a VM** |

Each carries its own commit body, its own suite additions, and its own §-numbered section appended
to `CLOUD_OBSERVABILITY.md`. They are four independent derivations of one design, not one branch
rebased four times: their diffs differ in structure (the first put the beacon in `bin/cc-cloud`;
the last three factored a shared `cc_cloud_return_contract` into `scripts/lib/cloud-create.sh`).

**Nothing on this row was ever blocked on knowing what to build.** The cost of the four dispatches
was paid entirely on re-derivation.

## 3 · The mechanism is already documented, and this row is a fresh instance of it

`docs/research/cloud-land-arm-strand-2026-08-27.md` measured 151 branches / 205 commits stranded on
an uncensored post-prune window. **Re-measured today, five days on: 234 branches / 353 commits.**
Same instrument (`git cherry origin/main <branch>` — patch-equivalence, never ancestry), same
uncensored window (branch tip after the one and only prune, 2026-08-19). All 291 post-prune
`claude/*` branches share history with trunk; **234 (80%) carry at least one unlanded patch**,
median 1 per branch, max 6.

| branch tip | branches | stranded | landed |
| --- | --- | --- | --- |
| 08-20 → 08-24 | 50 | 32 | 36% |
| 08-25 | 36 | 30 | 17% |
| 08-26 | 44 | 42 | **5%** |
| 08-27 | 45 | 44 | **2%** |
| 08-28 | 50 | 48 | **4%** |
| 08-29 | 41 | 22 | 46% |
| 08-30 → 09-01 | 25 | 16 | 36% |

The three days this row's first two implementations were written into (08-26 → 08-28) are the floor
of the whole window: **134 branches, 4% landed.** The four branches in §2 straddle it.

⚠️ **INSTRUMENT NOTE, recorded because it nearly produced a published number that was pure
artifact.** A cloud VM's checkout is **shallow** — this one cloned 50 commits of a 3,908-commit
trunk (`git rev-parse --is-shallow-repository` → `true`). Under that clone, `git merge-base
origin/main <branch>` fails for almost every branch, and the obvious reading — *269 of 290 cloud
branches have histories disjoint from trunk's* — is a statement about the local object store, not
about the fleet. `git fetch --unshallow` first: the real count of disjoint branches is **zero**.
Any strand, prune or landedness figure computed in this venue is wrong until the clone is deepened,
and this is the second time a measurement on this lane has been confounded by a purely local
property of the reader (compare the 08-19 prune censoring in
`cloud-land-arm-strand-2026-08-27.md` §1).

`scripts/cloud-return.sh`'s own header names the admission rule that produces the strand:

> `--sweep` acts ONLY on declarations carrying the W2 management fields (`notify_back` or
> `custody`). Every pre-W2 declaration — 20+ on this box, several with pushed, never-landed branches
> — was fired with nobody promising to land it.

A dispatch that fires **unmanaged** produces a branch that the return path is, by design, not
allowed to sweep. The work is pushed, correct, and unreachable. The row it belongs to stays `open`,
and `open` is `cc-dispatch`'s fire predicate — so the row is fired again, into a venue that will
produce another unmanaged branch.

**This is a different loop from the one the boot beacon closes**, and saying so is the point of
this section. The beacon fixes *absence is ambiguous* (a worker that has not pushed reads
`NOT-STARTED` and gets double-dispatched inside 15 minutes). It does **nothing** for *a pushed
branch nobody lands* — the row here, where four beacons-worth of finished work sat pushed for three
days. Both loops end in the same observable (a re-dispatch of a row that is not open), which is
exactly why the first was mistaken for the whole problem.

## 4 · Disposition

`faf78977` is the most complete of the four and the only one with a **live in-VM control** (beacon
pushed 4 minutes in, ref `87b320f6` present, work pushed on top). It was cherry-picked onto trunk
rather than re-implemented a fifth time — `git cherry-pick -x`, so the original sha and its author
survive in the trailer. None of the seven files it touches had changed on `origin/main` since its
merge-base (`17034cdb2`, 27 commits back), so it applied cleanly apart from one test-file hunk that
depended on its own branch-mate.

That branch-mate, `c0cda31d` (*an unset `ITERM_SESSION_ID` killed the verb instead of degrading
it*), was taken as a second atomic commit for a reason measured here rather than assumed:
`tests/cc-offload.bats` is **34/45 green on trunk on any box without iTerm**, and all 11 failures
are that one `set -u` crash. Without it, this row's own suite could not be asserted green by
anybody. With it: **46/46**.

**What was NOT done, and why.** No fix for the strand in §3 — it belongs to
`cloud-land-arm-strand-2026-08-27.md`'s row, not this one, and the honest cure (dispatching
`--managed`, or letting `--sweep` admit an unmanaged branch under a named rule) is a change to
`cc-dispatch`'s fire policy that a VM cannot verify. Filed here rather than acted on.

⚠️ **`cc-backlog done 0c8b39b67665` was not run, because it cannot be run from here** — the ledger
is `~/.claude/autonomy/backlog.jsonl`, which does not exist in this venue; the verb answers
`unknown id` and returns 3, writing nothing (`scripts/cloud-park.sh` header, measured 2026-08-29).
This artifact IS the close, on the branch channel §14 established, and `cloud-return.sh` step 8
turns the landed path into the `done`. **If this branch is not landed, the row is not closed — and
it will be dispatched a sixth time for exactly the reason recorded above.**
