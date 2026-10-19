# C2 judge: implementability and regression lens

Round 2, 2026-10-18/19. Adversarial judge (impl) for `C2-per-fact-latch.md`. The lens covers five questions:
- do the insertion points exist where the report cites them;
- what do the existing suites pin;
- which interpreter runs the code (bash 3.2, BSD awk/sed);
- what does it cost at runtime;
- does it keep one matcher per concept.

The only repo change I made is this file. My harnesses and outputs are in `/tmp/r2-C2-judge-impl/`. I read the
designer's `/tmp/r2-C2/` copies, TAP logs and data, and I ran their `sim2.py` with my own output path. I wrote nothing
under `/tmp/r2-C2/`. Load average was 273-334 throughout [M: `uptime`]. Each number is labelled [M] measured (with the
command) or [E] estimated (with the method).

**Verdict: below-90.** As a code change, C2 is clean:
- it applies to the worktree and to trunk;
- it passes every lint the land gate would run on these two files;
- it costs nothing measurable at runtime;
- I found no suite outside the four rewritten tests that pins the behaviour it changes.

The implementation is not what keeps it under 90. The designer's own measured limits do: about 9% precision on the
fires it recovers from the cap, and the incident's terminal close would still get the wrong demand (D1, not README §5).
I also found:
- two places where docs or comments drift from the new behaviour;
- one hardening gap in the fact key;
- a looser-than-needed ⛔ containment test;
- the fact that the 198-test suite has still never run as a single unit.

**Conviction 85**: my estimate that C2, with the changes listed in §8, is correct, safe and net-positive once landed. The
designer's 82 rested partly on unmeasured lost true positives. §6 measures those and finds them small, which raises
my figure. It still does not reach 90, because the change does not move the incident.

## 1. Insertion points: cited vs actual (worktree `84d63e3af`; hook byte-identical to the designer's base copy [M: `cmp`])

| Cited | Actual | Holds |
|---|---|---|
| SAFETY header `:83-85`, env-seam list ending `:102-105` | `:85` `# ── SAFETY`, `:105` PEER_OWNED_LIB line, `set -uo pipefail` `:106` | yes |
| `CLOSE` regex `:355` | `:355` | yes |
| `ca_first`/`ca_second` loop (hunk @ `:378`) | `:374-380`, `CA_VERDICT_ANCHOR` defined `:371` (before the new helper) | yes |
| ⛔ term comment `:1126-1129`, term `:1131-1135` | comment `:1126-1129`, `if [ "$RUNG" = "⛔" ]` `:1131`, `contra=1` `:1133` | yes |
| `_ca_exon` initialised before the ⛔ term (`set -u`) | `:935` `contra=0; facts=""; _ca_exon=""` | yes |
| D6 rung-line rule `:1476-1484` | `:1476-1480` inline `_d6_rl`, containment `case` `:1481` | yes |
| `N=0` / cap / FIRE (hunks @ `:1619`, `:1635`) | `N=0` `:1619`, cap `:1622`, `printf '%s %s\n' "$HASH" "$CLASS"` `:1638` | yes |
| ship floor HEAD read `session-continue.sh:1249` | `:1248` `head_sha="$(cd "$cwd" … git rev-parse HEAD …)"` | yes (±1) |

[M] The embedded diff in report §5.2 is identical to `/tmp/r2-C2/C2-hook.diff` (header lines excluded, `diff`).
- `patch --dry-run -p2` against a copy of the worktree hook: clean.
- Against `git show origin/main:hooks/completion-assert.sh` (dfdb5c273, which carries arm O b0f3971b8): all 7 hunks
  succeed, hunks 3-7 at offset +73, no fuzz.
- The test diff also dry-runs clean on trunk's `tests/completion-assert.bats`.

## 2. Interpreter and static checks

- [M] `/bin/bash -n` (3.2.57) is OK on the final hook and on the trunk-patched hook. The new constructs are
  `${FKEY:0:16}`, `${FKEY:+ $FKEY}`, `case … in *"⛔"*)` (a byte match) and a main-shell function with no `local`.
  All of them are 3.2-safe. The hook is not launchd-run: it runs from Claude Code's Stop chain through
  `#!/usr/bin/env bash` (bare path, `~/.claude/settings.json:1048`). The designer ran the incident replay under both
  3.2.57 and 5.3.15 with identical results.
- The new awk is `awk -v f=… '$3 == f {hit=1} END {exit(hit?0:1)}'`, the same idiom the hook already uses at `:1617`
  for `$1 == h`, so it is BSD-awk-safe. `FKEY` is hex, so `-v` escape processing cannot alter it.
- [M] `shellcheck` 0.11.0 gives rc 0 with no findings on the final hook and on the trunk-patched hook.
- [M] **pipefail-sigpipe-lint**, the land gate's ratchet, run on minimal git copies (`/tmp/r2-C2-judge-impl/pf-{base,final}`):
  - both have the same 5 grandfathered completion-assert sites, shifted +19 lines;
  - both report "clean (allowlist honoured)".

  The new pipes all drain: `| sed -E`, `| shasum`, and the moved `| grep -iE … >/dev/null`.
- [M] **bats-shellcheck-lint `--census tests/completion-assert.bats`** gives the same 2 inherited findings on base
  and final (SC2164 `:133`, SC1010 `:199`). C2 adds none.

## 3. What the existing suites pin

- **The four flips are real and the only ones.** I re-tallied the designer's TAP logs [M: `grep -c` over
  `/tmp/r2-C2/runs/*.tap`]:
  - base suite: 185/185;
  - patched hook on the unmodified suite: 181/185, red on exactly #11, #83, #84 and #111;
  - final filtered set: 19/19;
  - `-forks`: 8/8 on base and final. External calls are 155 at SHF_BASE, 99 at base and 102 at final.
  - `-assignee-shared-cwd`: 9/9.
  - `-durations`: 6/8, and A3 and C4 are red on the base control as well.
- [M] My own run of 3 final tests (`--filter '^cap: distinct false-dones|^FACT LATCH COMPAT|^FACT LATCH: a new commit'`,
  `CC_BATS_QOS=off taskpolicy -c utility`, sandboxed `CLAUDE_CONFIG_DIR`/`TMPDIR`/`CC_IDL`) gave 1..3, 3 ok, in 572 s.
- [M] **The 198-test suite still has not run as one unit.** I started it at load about 300. It finished 2 tests in about
  5 minutes (≈2.5 min/test, ≈8 h projected), so I stopped it. The designer's "green by composition" argument holds on
  reading. The new top-level `CA_BLOCKED_DOD_LEDGER=(…)` array is inert for other tests, and bats isolates tests. It is
  still an argument, not a run.
- By reading, nothing else pins the changed behaviour:
  - `stop-hook-forks-helpers.bash:96-107` `shf_same` compares state-file **names**, not contents, so the third
    column is invisible to it.
  - `why-tier.bats` P4 greps `arm="…"` literals, and C2 adds none.
  - `subagent-stop-r1.bats` and `-assignee-shared-cwd.bats` fire once per sid.
  - `session-writes.bats` and `operator-surface-scope.bats` only grep the source.
  - `research-relay-check.bats`: the relay arm writes two-column `relay` lines and reads `$1`/`$2` (`:336-341`).
  - Trunk's arm O writes `<hash> outbound` and reads `$1`/`$2 == "outbound"`. It exits before the ledger.
  - `completion-assert-outbound.bats` (g) asserts the next Stop falls through to `no-close-tell`, which runs before
    any C2 code.
  - No script keys on completion-assert `latched-*` reasons. `idl-abstain-alarm.sh` classes an unknown reason as DORMANT.
- **D6 and D7 cannot become newly reachable through the ⛔ guard.** The guard only runs at RUNG=⛔. D6 requires RUNG
  ∈ {✅, 👤} (`:1428-1429`) and D7 requires RUNG=👤 (`:1537`), so `contra_shape` dropping to 0 on a guarded close changes
  neither.

## 4. Runtime cost

- [M] Process count: +3 on the contradiction path only (`git`, `sed`, `shasum`), 99 → 102. I took this from the
  designer's forks TAP line `# done claim, ledger computed: 155 … before, 102 after`, and the base log reads 99.
- [M] Wall time (`/tmp/r2-C2-judge-impl/bin/ab.sh`): a hook-only A/B under `/bin/bash`, first fire on a 📦 ledger stub,
  base and final interleaved, fresh sandboxed state per run, n=10 each, load 273-310:
  - base: median 1,861 ms (1,172-2,248);
  - final: median 1,430 ms (1,205-2,683).

  The +3 forks are inside the noise, and there is no measurable regression. For context, the live registration has
  `timeout: 5` (`~/.claude/settings.json:1049`), and one evaluation already takes 1.2-2.7 s at this load. The headroom
  is the hook's problem, not something C2 adds to.
- `/usr/bin/shasum` is a `#!/usr/bin/perl` script [M: `file`]. Trunk's dfdb5c273 panic research finds that each `#!`
  exec retains about 1 KiB in `data.kalloc.1024`, so C2 adds one more `#!` exec per contradiction-path Stop.
  [E] That is on the order of 70/day (about 1,000 assert-path evaluations per 14 days, from report §0's 466 fired +
  492 capped), against a measured leak of 44-53 elements/s, or about 2×10⁻⁵ of the leak. That is negligible, but it
  runs against trunk's direction, so it is a free win to avoid where cheap (§8 item 3).

## 5. One matcher per concept

- **Met, and slightly improved.** The rung-line rule moves out of D6's inline block into the one memoised helper
  `_ca_rung_line`, which both readers call, so the copy count goes down. close-shape.sh has no rung-line function to
  reuse [M: `grep -n 'rung.line\|rung_line' hooks/lib/close-shape.sh`: comments only]. The ⛔ test reuses D6's
  containment semantics.
- The digit fold is a new normalizer. No existing helper does it [M: `grep -rn` for `s/[0-9]+/N/` over
  `hooks/ scripts/lib/ lib/`: none]. The HEAD read is the ship floor's own command.
- The memoisation has no practical effect, because D6 (RUNG ✅/👤) and the ⛔ term (RUNG ⛔) are never both reached
  on one Stop. It is harmless.

## 6. Regressions I probed (hook-only, `/bin/bash`, sandboxed seams; `edge.sh`, `edge2.sh`)

| Probe | base | final | Reading |
|---|---|---|---|
| E2 non-repo cwd, DoD count 2 → 1 | fire, fire | fire, `latched-same-fact` | as designed (digit fold, HEAD `?`) |
| E1′ {DoD; custody} → {DoD} → {DoD} → {DoD; custody} | fire, fire, fire, `capped:3>=3` | fire, **fire**, latched, latched | **the key is the whole facts string**: a subset is a "new fact" and re-convicts once. "Per-fact" is really per-facts-set. The replay keyed the same way, so the numbers are consistent. The name and the hook comment overstate it. |
| E3 "✅ Done — the ⛔ rung renderer fix is landed and live." over a ⛔ ledger | fire (BLOCKED ON YOU) | `exonerated:blocked-rung-stated` | containment false negative: a done-claim that only *mentions* ⛔ escapes |
| E4 "✅ Good to close: yes — everything is landed." / "⛔ One decision is still open…" | fire | exonerated | a YES verdict over an open decision escapes |
| E5 "⛔ Blocked — need your call on decision …" | fire | exonerated | intended |

How often E3/E4 happen [M: my `python3 -I` query over the designer's `/tmp/r2-C2/data/events.jsonl`, the 27 fires the
guard removes]: 13 have ⛔ as the first glyph, 14 are "❌ Good to close: no" with ⛔ on line 2, **0** are YES-verdict
and **0** mention ⛔ mid-line. So the designer's "all 27 genuine" holds, and the E3/E4 hole cost nothing in 14 days.
It is latent, and it is cheap to close (§8 item 6).

**Lost true positives, which the designer did not hand-read** [M: my query over `sim2.py --key head --k 1 --guard
blocked -dump`, which first reproduced 345 → 256 and 41 recovered in 31 sessions]:
- 112 actual fires go `fact-latched`: custody 52, unlanded 35, dirty 18, BLOCKED 5, dirty+BLOCKED 1, close-floor 1.
- The gap to the first conviction on the same key has median 48 s, p75 1,278 s and p90 4,956 s. 26 are more than
  30 min and 9 are more than 2 h.
- The only "✅ Good to close: yes" closes among them (66936177, 99e83151, e7659abe ×2) all sit on "dirty tree (89-90
  file(s)), authorship UNRESOLVED", which is shared-tree dirt. Those convictions are likely the arm's own false
  positives, so silencing them is not a lost catch.
- **Fact recurrence** means the fact cleared and came back on the same HEAD, for example a new dispatch on an unchanged
  lead HEAD. Only 21 of 457 latched evaluations had a strict `ledger-clean` record in between, and only 1 of those
  was a fire today: e739e5b5, an honest "❌ … still running" close.
- So the latch's lost-catch cost is small by measurement, not only by the park-word classifier.

**Fact-key hardening gap** [M]: BSD `sed -E 's/[0-9]+/N/g'` under `en_US.UTF-8` on an invalid byte prints
`sed: RE error: illegal byte sequence` and writes **nothing**. `FKEY` would then be `sha1("|<HEAD>")`, one key shared by
every such facts string, and unrelated facts would latch each other. The exposure is low, because `facts` is built
from the hook's own literals, numbers and hex shas. The guard is still one line.

## 7. Comment and doc drift the diff leaves behind

- `completion-assert.sh:1520-1530` (the D7 block) still says the ⛔ term "sets contra=1 for EVERY ⛔ close that gets
  this far". It also says "a CORRECT ⛔ close asserts no done-tell and abstains at the close-tell gate". That is the
  same false claim the diff corrects at `:1126-1129`. Behaviour is unaffected (D7 is 👤-only), but the file now
  contradicts itself.
- `hooks/lib/why-tier.sh:68` (`--why ledger`, which every ledger block points at) says RUNG=⛔ convicts, with no word
  about the stated-⛔ exoneration or the per-fact latch. A model that reads `--why ledger` after a `latched-same-fact`
  Stop is told the pre-C2 contract.

## 8. Required changes before landing

1. Fix the D7 comment at `:1520-1530` so it agrees with the new ⛔ term.
2. Add one clause each to `why-tier.sh`'s `ledger` topic: a ⛔ already stated on the rung line answers the ⛔ term, and
   a rewritten close over an unchanged facts string at the same HEAD is not re-convicted.
3. Never derive `FKEY` from an empty fold. Use the builtin the designer measured under 3.2
   (`shopt -s extglob; _f="${facts//+([0-9])/N}"`), which also drops the `sed` fork, or require a non-empty fold before
   hashing.
4. Run `tests/completion-assert.bats` whole (198) at normal load, plus `tests/completion-assert-outbound.bats` on the
   trunk-rebased tree. Neither has run as a unit.
5. In the hook comment and test names, say "facts string" where it says "fact". A subset of a convicted set convicts
   once more (E1′).
6. Optional, closes E3/E4 at no cost on the 27: within `_ca_rung_line`'s line(s), require ⛔ as the first glyph after
   markup, or require that the verdict line is not a yes. The rung-line definition stays shared.

None of these changes the measured figures (345 → 256, 41 recovered).

## 9. Why below-90

The change is implementable as specified, at about 92% on this lens [E: §1-§6, with the unrun whole suite as the main
residual]. The candidate does not clear 90, for the designer's own measured reasons, which nothing in this lens
overturns:
- about 3.5 of the 41 recovered fires are true positives;
- the ledger arm's first conviction of a stated park is untouched, so constraint 2 is only partly met (222 → 148
  wait-worded blocks);
- the incident's terminal close fires D1 at the settings.json step, not at README §5.

C2 is a safe enabler for a follow-on or DoD-seam arm, not the fix.
