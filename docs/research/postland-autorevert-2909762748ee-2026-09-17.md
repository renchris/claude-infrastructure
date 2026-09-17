# post-land AUTO-REVERT `tests/effort-parity.bats` @ `2909762748ee` — ALREADY CURED

- **Row:** cc-backlog `a9ce24de2cfe` (project `claude-infrastructure`)
- **Verdict:** **ALREADY CURED on trunk.** Cure sha `3b45618bbb4eadc6e59eb8592ec90cb23ae062bc`
  ("fix(effort-parity): re-land the launcher fix, and invert the test that reverted it"), landed
  2026-09-17T19:18:47Z — **27 minutes before this row was dispatched.** No code change was needed
  and none was made; this document is the deliverable.
- **Adjudication of the revert:** the auto-revert's **attribution was correct** and its
  **conclusion was wrong**. The fix really did redden the suite; the suite encoded the defect.
  Trunk now carries the fix *and* a live red-proof against re-reverting it.
- **Duplicate row:** the same red was already driven to landed by a sibling cloud session under
  cc-backlog `9b56be1f86b8` (`Cloud-session: session_01SDcaqMRSCVeNPpMg5mdwoK`). Two rows, one red.
- Measured off-box on an Anthropic-managed VM, 2026-09-17T19:48Z, at `origin/main` with
  `git rev-list --count HEAD..origin/main` = 0 and `origin/main..HEAD` = 0.

## 1. The four commits, all four ancestors of `origin/main`

```
$ for s in 6202beaa 2909762748ee… ab16fb3eeb33… 3b45618bbb4e…; do
    git merge-base --is-ancestor $s origin/main && echo "  ancestor: ${s:0:8}"; done
  ancestor: 6202beaa   docs(routing): …                 (the culprit's PARENT)
  ancestor: 29097627   fix(effort-parity): the launcher check read the legacy track's knob
  ancestor: ab16fb3e   Revert "fix(effort-parity): …"   (the AUTO-REVERT — it applied)
  ancestor: 3b45618b   fix(effort-parity): re-land the launcher fix, and invert the test
```

Note the class: this is **AUTO-REVERT LANDED**, not the rc=90 conflict case. The revert applied,
so trunk genuinely carried the reverted (buggy) check from `ab16fb3e` until `3b45618b`.

## 2. The culprit's functional fix is byte-identical on trunk

The complete diff from the convicted commit to `origin/main` in the accused file is **one header
comment**, and it is a *further* correction in the same direction (the header still advertised the
wrong knob as GATING):

```
$ git diff 29097627 origin/main -- scripts/effort-parity-assert.sh
@@ -11,7 +11,9 @@
-#   (a) the launcher --effort default in ~/.zshrc (CLAUDE_DEFAULT_EFFORT:-<v>) — GATING: …
+#   (a) the MODERN launcher `claude()`'s --effort default in ~/.zshrc — GATING: != SSOT default = drift.
+#       Its knob is ${CLAUDE_EFFORT:-${CLAUDE_OPUS5_EFFORT:-<v>}}. The legacy `claude-prev` track's
+#       CLAUDE_DEFAULT_EFFORT is a SEPARATE knob by design and is reported NON-gating (see § (a) below).
```

Nothing else. So re-deriving the cure here would have produced a diff that reverts trunk.

## 3. The post-land RED does not reproduce on trunk — and the plan line is present

```
$ bats tests/effort-parity.bats          # bats 1.14.0, cloned for this run
rc=0
1..11
ok 1 .. ok 11
```

The plan line `1..11` is asserted explicitly: an absent `not ok` is not a pass
(memory: *A gate refusal is not a gate result*).

## 4. The attribution arm — the suite is NOT green-by-weakening

A fix that merely makes a check unable to go red is the same defect inverted, so green-on-trunk
alone settles nothing. I ran **trunk's suite against the REVERTED script**, one variable, the two
files otherwise untouched (`git show ab16fb3e:scripts/effort-parity-assert.sh` swapped in, then
restored — `git status --porcelain` clean afterwards):

| arm | script | result |
|---|---|---|
| trunk | `origin/main` | `ok 1..11`, rc 0 |
| pre-fix control | `ab16fb3e`'s reverted script | **`not ok` 1, 3, 4, 5, 6** · `ok` 2, 7, 8, 9, 10, 11 — rc 1 |

This **independently reproduces the re-land commit's own attribution table, row for row**
(`vs pre-fix: not ok 1, 3, 4, 5, 6  ok 2, 7, 8, 9, 10, 11`) — I did not take it on the commit
message's word. Exactly the five launcher cases move; the six unrelated ones are green in both arms.

Case 4 is the load-bearing one: it is the old convicted case 3 **inverted in place**, so a future
revert of this fix goes red *there* and names why. The pre-fix arm shows it firing. The red-proof
against this specific regression is live, not asserted.

Case 1 also moves, confirming the re-land's claim that it had been green-and-decorative (it
asserted only the exit code while the gating grep matched nothing in the fixture).

## 5. Why the revert was wrong — the mechanism, confirmed from in-repo evidence

The convicted case wrote one fixture line, `alias claude="claude --effort ${CLAUDE_DEFAULT_EFFORT:-high}"`,
and demanded DRIFT on it. `CLAUDE_DEFAULT_EFFORT` is the **legacy `claude-prev` track's** knob. The
modern `claude()` resolves `${CLAUDE_EFFORT:-${CLAUDE_OPUS5_EFFORT:-…}}` and never reads it — so
the case **demanded exactly what the cure removes**, and a test demanding the disease undid the cure.

Two in-repo records that PREDATE the fix corroborate the knob split independently of it:
`docs/plans/backlog-consolidation-2026-08-09/OUT-accounts.md` (the `claude()` → `CLAUDE_EFFORT`
resolution, naming this very fixture as the trap) and
`docs/research/fable51-vs-opus5-routing-2026-09-16/A6-mechanics.md` (line 495 is the effort emitter).

This is the shape our corpus already names as **[DoD can demand what the cure removed]** and
**[A fixture blind to the axis under test holds it constant]**, arriving through the auto-revert
actuator: the actuator's reachability attribution was right, and the *premise it never re-measured*
— that a red suite means a bad diff — was the wrong half.

## 6. Dispatcher vintage: EQUAL

```
$ git rev-parse origin/main:bin/cc-dispatch
27c461a5f1a4de551fdfbe2a619e28e696c13aaa
```

Identical to the blob named in the brief, so the dispatcher that fired this row **is** trunk. No
landed-but-not-live gap to account for on that path.

## 7. The stored falsifier's `exit 1` was correct-by-contract, not a defect

The brief's probe ran `postland-verify.sh --falsify-red tests/effort-parity.bats 2909762748ee` and
returned 1 (NOT REFUTED) against a row whose cure had landed 27 minutes earlier. That is the
probe's documented asymmetry working as designed, and it is worth stating so nobody files it:

`verb_falsify_red` does not re-run the suite (it could not fit cc-premise's 20s bound). It retracts
**only** when the recorded full-corpus `last-green` is a *descendant* of the accused commit, and
`STATE/last-green` advances only on a full-corpus pass. Twenty-seven minutes after the re-land, no
such pass could yet exist, so the ancestry clause returns 1 — "asked, answered no", read by
cc-premise as *still live*, the safe direction. The span clause is not implicated:
`tests/effort-parity.bats` is **not** in `scripts/host-suites.manifest`, so it is inside the corpus
and a green would cover it.

⇒ A stored falsifier keyed on a *green pointer* is structurally blind to a cure landed inside the
window before the next full-corpus pass. That is the correct polarity (a false retraction would
close a live red) and it means **an unrefuted premise is exactly the non-verdict the brief says it
is** — the trunk read in § 2–4, not the probe, is what settled this row.

## 8. What I ran

```
git rev-parse --is-shallow-repository && git fetch --unshallow      # arrived SHALLOW at depth 50
git fetch origin -q && git rev-list --count HEAD..origin/main       # 0
git rev-parse origin/main:bin/cc-dispatch                           # == brief's blob
git merge-base --is-ancestor <each of the 4 shas> origin/main        # all 4 ancestors
git diff 29097627 origin/main -- scripts/effort-parity-assert.sh     # one header comment
git log --oneline 29097627..origin/main -- scripts/effort-parity-assert.sh
bats tests/effort-parity.bats                                        # trunk: 1..11, rc 0
bats tests/effort-parity.bats  # with ab16fb3e's script swapped in   # rc 1, reds 1,3,4,5,6
grep -n tests/effort-parity.bats scripts/host-suites.manifest        # absent ⇒ in corpus
```

`git status --porcelain` clean after the control arm; the only tracked change on this branch is
this document.

## 9. Residual, stated rather than hidden

- The four **BELOW** rows on the live host (four of five `settings.json` under the floor) are
  unchanged and still real. Realigning them is the operator's class-C step, cc-backlog
  `01cbf0842c09`; `effort-parity-assert.sh` only reports them. Not this row's scope.
- I could not read the backlog store or the `last-green` pointer from this VM, so § 7's account of
  why the probe answered 1 is derived from the verb's own source and the landing timestamps, not
  from the live state file. The conclusion it supports — that the probe's answer was a non-verdict
  rather than a confirmation — does not depend on the pointer's exact value.
- No `cc-backlog done` was run (a no-op off-box, per the brief). The desk closes
  `a9ce24de2cfe` from this landed content, citing `3b45618b` as the cure.
