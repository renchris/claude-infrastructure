---
status: in-progress
---

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

---

## 4. Known-open, deliberately not laundered

Silencing the notification does **not** make the partition green. Whether the underlying `red` is a
true statement about the tree is tracked separately — see
`docs/research/ci-notification-flap-2026-08-15/C-is-the-red-true.md`. The fix above changes only
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
