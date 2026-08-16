---
status: complete
---

> **DONE 2026-08-15.** The notification defect is fixed, landed (`e5b82629a`, `6e73c5089`,
> `23f6bef80`) and verified on the production cron: scheduled runs went `failure · failure ·
> failure · **success**`, with `verdict` skipped and the fold still honestly `red`. The separate
> "the partition emits no greens" problem is filed as `ea3ea8f145f9`, and the other repos'
> producers as `485f8f87eb5f` · `9333991e4544` · `54d7aff8ed8d` · `e3f988b489c3`. This plan is
> closed; those ids carry the remainder.

# CI green-producer notification — "Run failed" every hour, forever

## Phase 0 — execution locus

**L (lead-inline), one wave, justified:** the whole change is two files in one repo and its
load-bearing facts are three GitHub API semantics that had to be *measured* in sequence (probe →
read result → design). Splitting that across sessions would hand a successor the conclusion without
the measurement. Read-only breadth ran as four background research subagents (A-D, artifacts in
`docs/research/ci-notification-flap-2026-08-15/`); no subagent wrote code.

Lead context budget: this work is fully persisted here + in the commit message, so the successor
point is "after the live verification in §6" — everything before it is reconstructible from disk.



**Scope (frozen):** find every GitHub Actions workflow flooding the operator with "Run failed"
mail, across all repositories; design and implement the 100th-percentile long-horizon fix; land it
and verify it live.

Started 2026-08-15. Research artifacts: `docs/research/ci-notification-flap-2026-08-15/`.

---

## 1. The finding, stated as a conclusion

`hermetic` is a **green-or-nothing producer that was spelling "nothing" in GitHub's error channel.**

It is not flapping and it is not a regression. It has failed **96 of 100 runs since the workflow was
born**, 89/91 of the last four days' scheduled runs, because "the partition is not green" was
encoded as `exit 1` — and a non-zero exit is how GitHub says *error*, which is wired to the
operator's inbox. At `cron: '17 * * * *'` that is ~22 emails/day carrying one bit that never changes.

The workflow's own header had already named the hazard, one paragraph above the defect:

> a check that is red on every commit carries the same zero bits as one that cannot fire, which this
> repo has paid for before.

So the doctrine was right and merely **unenforced**. That is the whole story: this is a
documentation-vs-implementation gap, not a bug anyone introduced.

### Why "just exit 0" would have been catastrophic

`scripts/offbox-green-pull.sh:43` reads `JOB_NAME="${CC_OFFBOX_JOB:-verdict}"` and mints an off-box
green **iff** the check-run of that name reads `completed:success`:

```
repos/{nwo}/commits/{sha}/check-runs  →  select(.name == "verdict")  →  status:conclusion
  success → write the green stamp
  *       → write NOTHING     # "This producer may acquit; it may not convict."
```

An unconditional `exit 0` therefore mints a green **for every tree, including red ones** — it would
have converted a noise problem into a correctness problem in the store the deploy lane trusts.

---

## 2. What was measured, not assumed

GitHub does not document the two facts the fix turns on, and research found the third actively
**disputed** between sources. All three were measured on throwaway probe runs
(`31913525656`, `31913525664`, branch `probe-conclusion-semantics`, since deleted):

| arm | check-run conclusion | RUN conclusion |
|---|---|---|
| job skipped by `if:` on a needs-output | `completed:skipped` | **success** |
| same job when the gate passes (control) | `completed:success` | success |
| `continue-on-error: true` on a failing job | `completed:failure` | **success** |

The control arm matters: without a job that genuinely succeeded, a `success` run conclusion would be
explained equally well by "nothing ran".

**`skipped` is not `success`**, so the puller falls to its no-op arm — byte-identical to what it did
when the job exited 1. The consumer needs no change whatsoever.

### The option space, and why the others lose

Established by research against live docs (`docs/research/.../D-notification-levers.md`):

- There is **no `neutral` conclusion** for an Actions job — only for a self-created check-run.
- There is **no per-workflow notification mute**, anywhere. Every suppression lever is account-wide
  (`Settings > Notifications > Actions`) or repo-wide (unwatch). Both hide real failures elsewhere.
- `cancelled` still notifies. A per-workflow `notifications:` YAML key does not exist.
- `continue-on-error` works (measured above) but keeps publishing `failure` as the check-run — i.e.
  it keeps *convicting*, and merely asks GitHub to tolerate the conviction. That contradicts the
  producer's own doctrine.
- A self-created check-run (`checks: write`) or commit status would work, but needs a new
  permission, a new API call, and decouples the signal from the name the consumer already reads.

The gated skip needs **no new permission, no new API call, and no consumer change** — and it says
exactly what the doctrine says, in the only vocabulary GitHub has for it.

---

## 3. What shipped

`8e8e0f063` — `.github/workflows/hermetic.yml`, `tests/offbox-partition.bats`.

- The old `verdict` job is renamed **`fold`**: same checkout, same shard download, same fold, same
  step summary, same `offbox-verdict.json` artifact. It now **reports without convicting** and
  always exits 0. It exposes `outputs.verdict`.
- A new job named **`verdict`** — the exact name the puller reads — is gated
  `if: needs.fold.outputs.verdict == 'green'` and does nothing but succeed. Green ⇒ it runs and
  publishes `completed:success`. Not green ⇒ it is skipped, and the run concludes `success`.

**This is not a mute.** If `fold` dies, or a `suite` job's runner fails, those jobs fail and the run
fails with them — and the operator is emailed, correctly. Only the null result went quiet. (The
suite jobs exit 0 on test failure by design; verified across every recent failing run, where all 11
suites read `success` while the fold read `red`.)

### The recurrence guard

Tests 26-28 in `tests/offbox-partition.bats` — that file already names `hermetic.yml` as a subject,
so `gate-select.sh` already routes workflow edits to it. The contract is read from **both** halves
so the two files cannot silently disagree: the job name is parsed out of `offbox-green-pull.sh`
rather than restated.

- **26** the shipped workflow satisfies the contract.
- **27** CONTROL — re-introducing `exit 1` turns it red (the noise half).
- **28** CONTROL — removing the green gate turns it red (the false-green half).

Both controls are anchor-checked: the mutation is asserted to have applied before the check runs, so
a green cannot come from a mutant that was never built.

**Test 28's anchor was itself dead on first write, and the land gate caught it.** It was spelled
`! grep -q …`, and bash exempts a `!`-negated command from errexit — so the anchor passed whether or
not the mutation applied. A vacuous anchor on a control is the precise failure the control exists to
prevent, one level up. Re-spelled as `run` + `[ "$status" -ne 0 ]` and verified in BOTH directions:
the new form fails on an unmutated file, the old form passes on one. (The repo's own
`bats-assert-liveness-fix.py` is known to emit repairs that fail on both branches — board #100 — so
this was hand-fixed and mutant-verified rather than auto-repaired.)

---

## 4. Known-open, deliberately not laundered

### The partition is structurally red, and that is a SEPARATE problem — backlog `ea3ea8f145f9`

Measured 2026-08-15 from the `offbox-verdict` artifacts of four consecutive runs. Exactly **one
suite fails per run, and its identity rotates**:

| run | failing | suites |
|---|---|---|
| 31912550182 (22:35) | `tests/deathwatch-watchfile.bats` | 427 |
| 31909790008 (21:34) | `tests/cc-close-attrib.bats` | 426 |
| 31907172661 (20:37) | `tests/unattended-path-lint.bats` | 427 |
| 31904202657 (19:32) | `tests/unattended-path-lint.bats` | 427 |

**Why this matters for the remedy, and why nothing was excluded.** The research pass concluded the
red "reduces to exactly two suites" and proposed excluding them. Re-reading the artifacts directly
refuted it: a third suite had already appeared in the newest run. The axis is not *which* suites —
it is **per-run flake probability across 427 of them**. Excluding today's names is O(n) whack-a-mole
that would go green for one hour and re-red on a different name, while permanently shrinking the
partition for a reason that was never machine-coupling. So the exclusion manifest was deliberately
**left untouched**.

This is the same shape this repo already measured for the on-box monolith — P(green) 2.3%, which is
why the full-suite verdict moved off the land path entirely. It is a real problem and it is not this
one.

It also **retroactively justifies the fix above**: a producer that is red most of the time for
structural reasons is exactly a producer whose "not green" must never be an error email.

### The rest

Silencing the notification does **not** make the partition green. The fix above changes only
*how a non-green is reported*, never *whether the tree is green*, and no green is minted that was
not minted before.

Related open board items that may or may not be the same suites (must not be assumed to be):
#112 (fire-autonomy + notify-back red on pristine trunk), #126 (tsv-field-collapse), #117 (trunk
full-suite red, count swinging 3..14 ⇒ mostly flakes).

---

## 5. Cross-repo

See `docs/research/ci-notification-flap-2026-08-15/A-crossrepo-census.md` for the ranked
failed-runs-per-day table across every repo. Prior task #157 fixed the `diagrams` source durably
(15/15 green) but never touched `hermetic`, and closed anyway — which is why the symptom outlived
its own fix.

**Only 4 of 114 repos produce any Actions run at all** (110, including all 24 forks, are
mechanically incapable of emailing). Ranked by failed runs/day:

| producer | /day | verdict | disposition |
|---|---|---|---|
| `claude-infrastructure` **hermetic** | **8.29** | the null-result-as-error defect | **FIXED** here |
| `claude-infrastructure` diagrams | 4.07 | REAL content-drift catches; last 20 runs all green | none — the gate is working |
| `lakehouse-lecture` pages-build-deployment | 1.57 | GitHub's own Pages Liquid parser on literal `{%…%}` | filed `54d7aff8ed8d` |
| `doc_classifier` nightly | 1.07 | 15/15 red, `make scale-run SCALE_POINT=proving` | filed `9333991e4544` |
| `reso` soketi-image-cve-scan | 0.14 | **TRUE positive** — green until 2026-06-29, red since on unpatched CVE-2026-59874 | filed `e3f988b489c3`; should stay red until patched |
| `reso` tenant-drift | 0.14 | dies at `pnpm/action-setup`; **has never once reached its own check** since 2026-05-24 | filed `485f8f87eb5f` |

`hermetic` alone was more than every other workflow combined, which is why the perceived cadence was
"every 30 minutes". The reso `tenant-drift` row is the one worth reading twice: a config-drift check
that has been dead for ~3 months while still rendering as a run in the Actions tab — the failure mode
where a broken alarm is *worse* than no alarm, because it also manufactures the belief of coverage.

---

## 6. Live verification — run `31914770411`, on the landed tree

Dispatched on `db942f294` (trunk had advanced past the land; the workflow file there was
content-verified to carry the fix before reading anything from the run).

| signal | before | after | meaning |
|---|---|---|---|
| RUN conclusion | `failure` | **`success`** | the email stops |
| `verdict` check-run | `completed:failure` | **`completed:skipped`** | not `success` ⇒ puller writes nothing |
| fold verdict | `red` | `red` | unchanged — no green was manufactured |

Both halves hold simultaneously, which is the whole claim: **the run stopped failing without the
producer starting to lie.**

### What the same run then exposed

Its one failing suite was `tests/offbox-partition.bats` — the suite added *by this change*. Tests
26-28 imported PyYAML, which the GitHub macOS runner does not have, so the contract check convicted
the partition it exists to protect. Reproduced locally by hiding the module (exactly 3 not-ok,
matching the runner's `ok=26 notok=3`), then rewritten onto stdlib `re` only and re-verified with
PyYAML present *and* hidden: identical, all green, both controls still red on their mutants.
Fixed in `6e73c5089`.

The irony is worth keeping: a test asserting "a check must be able to run where its subject runs"
was itself unable to.
