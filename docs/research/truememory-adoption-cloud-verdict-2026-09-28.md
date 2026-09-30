# TrueMemory adoption, cloud dispatch — verdict: already cured on trunk (2026-09-28)

**Row:** cc-backlog `eb41b669e5e6`, "TrueMemory adoption: build-now waves A-C (14 items)".
**Branch:** `claude/fire-20260928T081233Z-36901-1` (cloud VM, dispatched 2026-09-28T08:12Z).
**Verdict:** DONE on trunk. The desk's own wave sessions (`tma-wave-a/b/c`) landed every build-now
item (#1-#14), the #35 benchmark, and Waves D-E. `docs/plans/TRUEMEMORY_ADOPTION.md` on trunk reads
`status: complete`, with Waves A, B and C each marked `DONE 2026-09-28`. The program-complete commit is
`9eb53312`. This branch lands no code: this file is the whole diff.

## Evidence

Each cure sha below is the one cited in trunk's plan. Each was asserted with
`git merge-base --is-ancestor <sha> origin/main` (exit 0) against `origin/main` = `e5a83f80`, unshallowed.

| Item | Cure sha(s) on trunk |
|---|---|
| #1 situational truth + delivery contract | `6b1afce14` |
| #2 session-index coverage (P0, P0b, P1) | `bef0303d4` `9ce845cb0` `ce235bc70` |
| #3 expected-fires registry | `d08ab07ab` `dde03ca37` |
| #4 cc-memory-search + consumers | `910f86140` `045c8f334` `974122f01` |
| #5 memory-eval harness | `5224eec5e` |
| #6 + #7 symptom-to-lesson + sanitizer | `bf2524ed8` `4a5b11919` `1d46ca69d` |
| #8 reach audit + native-pass sentinel | `cf32f48ff` |
| #9 visible cold-tier pointer | `5070c4488` |
| #10 whole-store neighbour advisory | `bd56935ab` |
| #11 local store history | `46a55dc07` |
| #12 structured supersession | `c92df1f22` `23064fd9d` |
| #13 link integrity | `1791e0cca` `fc31ebf1e` |
| #14 transcript normaliser | `99e85a822` `6890375c2` |
| #26 shadow | `e2d44ff12` |
| #35 delivery benchmark (no gain) | `9fe735df7` `ddf721d05` |
| autoDream-pin migration, rejection record | `59331fee0` `b531da930` |
| program complete | `9eb53312` |

**Dispatcher vintage:** `git rev-parse origin/main:bin/cc-dispatch` = `dc9130372d63…`. That equals the
blob that composed the brief, so the dispatcher that fired this session IS trunk's.

## What this session did, and why none of it lands

When the session booted, `git rev-list --count HEAD..origin/main` was 0. Trunk then held Wave A and
part of Wave B (#5, #6, #7, #10, #26). It did not yet hold #4, #9, #12, #13 or #14, and the plan on
trunk still read Wave B "BLOCKED on Wave A" / Wave C "BLOCKED on Wave B". So the session built #4, #12
and #14 and started #9 and #13 in parallel. The duplicate commits, now discarded, were `2c823a1e` (#4),
`d6a966a7` (#12), `97416980` (#4 consumers), `24eb9386` and `efbb5439` (#14).

A re-fetch before the last push showed 73 new trunk commits. Among them were the desk's own #4, #9, #12,
#13 and #14, plus the program-complete commit. Replaying the cloud commits would add/add-conflict on
`bin/cc-memory-search`, `hooks/lib/transcript_norm.py`, the registry and the nightly steps, and at best
would land a second implementation of each. So the branch was reset to `origin/main` and carries only
this verdict. Per the brief: do not invent code work to justify a push.

## Finding for the dispatcher (the reason this row cost a duplicate build)

The row was dispatched while desk sessions were still driving it:
- The desk's #4 commit `910f86140` was AUTHORED 2026-09-28T00:50-05:00 (05:50Z), 2 h 22 min before
  this dispatch at 08:12Z.
- The desk's #9 and #14 were authored at 11:00Z-11:03Z, while this VM was building the same items.

A row whose program is being driven wave by wave by live desk sessions looked `open` to the dispatcher,
so it fired a second venue over the top of them. The brief's own shallow-clone and moving-trunk warnings
could not catch this, because at boot the cure was genuinely not yet on trunk. The duplicate was in
flight, not landed. A dispatcher guard keyed on "a desk session owns this row now" (a `tma-wave-*`
custody row, or a plan section marked in progress with a live owner) would have prevented it.
Re-fetching trunk before each item, rather than only at boot, is what exposed it here.

## Incidental, recorded read-only (Linux box only; the operator box is macOS)

- Several suites are red on this Linux VM on trunk itself, identically with or without any change. The
  cause is BSD-only calls: `stat -f %m`, `date -r <epoch>`, `plutil`. Affected: `idl-abstain-alarm.bats`
  #1, `mem-neighbours.bats` #12/#13/#15, `memory-nudge-ruling-shadow.bats` #15,
  `cc-instructions-variant.bats` #1/#2/#5, `install-resident-reload.bats` #1/#4/#6/#7/#14, and
  `nightly-regression.sh --selftest` (2 plutil reds).
- On GNU `stat`, `-f` means FILESYSTEM stat and exits 0 with a paragraph of text. So a
  `stat -f %m f || stat -c %Y f` fallback never reaches its GNU arm. Relevant only if these scripts are
  ever meant to run off macOS (the autonomy-core installer's Linux target, `5bd2fdce`).
