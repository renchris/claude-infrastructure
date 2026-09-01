# The "halving context ≈ +50% capacity" lever is cured on trunk — verdict on a third dispatch

**2026-09-01.** Backlog `564d151b76e5` (DECIDE) — *"`scaling-bottlenecks-2026-08-09.md:36,150` still
prescribes 'halving context = +50% active capacity' but Opus-5 cache-read measures 0.000 and
`exchange-rate.md:223` advises the opposite — two repo docs contradict, neither cites the other"* —
was dispatched to a `--venue cloud` session for the third time. **Its premise was cured on 2026-08-24
and the cure was extended on 2026-08-29. Nothing in the row's cited list needed doing.**

This is the §14 verdict artifact (`docs/plans/CLOUD_OBSERVABILITY.md` § 14): a cloud worker that
finds its row already cured lands a `docs/research/*.md` naming the cure sha, the verification it
actually ran, and the evidence — because a no-op dispatch that pushes nothing is indistinguishable,
from the desk, from a worker that never booted. It does not invent work to justify the push.

## 1 · The row's premise, clause by clause

| the row's clause (written 2026-08-19T12:58:33Z) | disposition on trunk today |
|---|---|
| `scaling-bottlenecks-2026-08-09.md:36` prescribes the lever | **struck** — line 36 carries the clause in `~~strikethrough~~` plus 🚨 *STRUCK 2026-08-24 — REFUTED by measurement; see §2a* |
| `…:150` carries it into standing policy | **struck** — the §2a insertion pushed that bullet to **:255**; it is struck with the same note. *Chase the section, not the number; every external citation of `:150` predates 2026-08-24* |
| `exchange-rate.md:223` gives opposite advice | **still does, and is now correct and cited** — R1 is unchanged; the meter governs |
| **"neither cites the other"** — the actual defect | **cured.** `scaling-bottlenecks-2026-08-09.md` **§2a** (:39) and `exchange-rate.md` **§ R1 — what it superseded** (:231) now cite each other explicitly, with the chain of custody named in both |

The ruling is class **A** (an agent ruling on evidence: a meter measurement superseding an
unvalidated composition model, no operator value fork). Reasoning, arithmetic and the
bound-not-a-point caveat are in §2a and are **not restated here** — that section and the two commit
bodies are the record.

## 2 · The cure — two commits, both ancestors of `origin/main`

    a299123b06d0885e9d4e93ead3ecfcb50c3f405c  2026-08-24
      docs(quota): strike "halving context ≈ +50% capacity" — measurement supersedes the composition model

    7bb14728a7e4f105a6ea10c95e04810a8836f4f8  2026-08-29
      docs(quota): propagate the struck cache-read lever to its origin and the jcode cluster

`git merge-base --is-ancestor <sha> origin/main` → **0** for both, against `origin/main` at
`0d629315`. See §4 — that check answered **NO** for both on first run, and the negative was an
artifact of the container, not a fact about trunk.

`a299123b` struck the two cited sites and made the docs cite each other. `7bb14728` found what §2a
had missed — the lever's **origin**, `scaling-bottlenecks-2026-08-09/07-accounts-api.md` §6.4, which
every other carrier cites as its source and which §2a left live for five more days — and reversed
§2a's "leave the jcode carriers as dated audit records" disposition on the ground that a ranked-lever
table issuing a live stop-work order is prescriptive text, not an audit record.

## 3 · Verification actually run, not recalled

Working tree byte-identical to `origin/main` across `docs/` (`git diff origin/main -- docs/` empty),
so every read below is a read of trunk.

**Every carrier, struck or resolved:**

| file | site | state |
|---|---|---|
| `scaling-bottlenecks-2026-08-09.md` | :36, :255 (ex-`:150`) | struck; §2a :39, §2b :112 |
| `scaling-bottlenecks-2026-08-09/07-accounts-api.md` | §6.4 :294 | struck at the **origin**; §6.4a :311 replaces it |
| `usage-telemetry-100p-2026-08-16/exchange-rate.md` | R1, § :231 | correct; now cites the ruling |
| `jcode-due-diligence-2026-08-11.md` | :53, :129 | struck |
| `jcode-due-diligence-2026-08-11/bottleneck-audit.md` | :73 | struck |
| `jcode-due-diligence-2026-08-11/ranked-levers.md` | :44, :62, :116 | struck / re-priced / settled |
| `memory-econ-rearchitecture-2026-08-10/prior-art.md` | :137, :138 | rows 55/56 marked REFUTED / CORRECTED |
| `orchestration-units-2026-08-19.md` | N7 :298 | ✅ DECISION FILED |
| `orchestration-units-2026-08-19/A6-VERIFY-quota-economics.md` | :318-345 | ✅ FILED AND DISCHARGED, naming both shas |
| `orchestration-units-2026-08-19/Z-completeness-critic.md` | G15 :277-292 | ✅ CLOSED |

A repo-wide grep for `halving context` / `+50% active` / `68%`-with-cache-read returns **no unstruck
prescriptive carrier**. The remaining hits are the strikes themselves and the audit records that
quote the original claim, each carrying its own resolution note.

**The live policy layer was already correct and needed nothing** — `hooks/cache-expiry-warning.sh:47`
tells sessions in so many words that *"shrinking the context does NOT save quota"*, and
`:18` records that `cache_read` is charged at ~nothing against the weekly limit while
`cache_creation` is 42–48%. Only docs were ever stale, which is why no behaviour changed in 15 days.

**The citation chain is complete end to end** — the row's actual complaint. N7 → §2a → §2b →
`07-accounts-api.md` §6.4a → `exchange-rate.md` finding #8 / R1, each link present in the file, in
both directions where the correction is mutual.

## 4 · The shallow-clone trap reproduced — a fourth instance

`git merge-base --is-ancestor` answered **NO** for *both* real ancestors, and
`git log origin/main -- <the three cited paths>` returned exactly **one** commit (the graft). Both
readings say *"the cited cure is not on trunk"* — the precise premise that licenses re-deriving a
diff, i.e. the trunk-reverting failure `6110fc45141e` names. This container grafts at **50** commits;
`git fetch --unshallow` moved the count to **3,933** and the identical check answered **YES**.

This is already documented and is **not re-derived here**: `docs/plans/BACKLOG_DRAIN_24_7.md:28843`
("THE SHALLOW-CLONE TRAP") states the rule — *`git rev-parse --is-shallow-repository` before any
`--is-ancestor` or path-history read, and deepen before believing a negative* — and
`docs/plans/MASTER_ENFORCING_STORE.md:182` records the third instance. This entry is the fourth, and
it is worth one line only because the trap sits directly on the **first step the dispatch brief
itself prescribes**, so a worker obeying the rails hits it by construction. The content check
(`git show origin/main:<path>`) is the one that survives a shallow clone, and it is what settled this
row before ancestry could be resolved at all.

## 5 · What this does NOT close, and why it is not re-filed

`7bb14728`'s body names one item **rather than filing it**, deliberately: whether L7 still ranks #1
on the resident axis alone once its quota half is removed. Its score `(18 × 0.95)/1 = 17.1` uses an
18 that the row's own arithmetic (`148 − 132 = 16`) does not derive, so a re-score must first recover
what the 18 was — a fresh analysis, not a propagation of this ruling. Both ranking tables carry a
provisional-ranking banner instead of a silent re-rank on a number nobody can reconstruct. That
disposition stands and is **not** re-filed here.

Also still open and named as such in §2a: **which of the two fits is true** (the cache-read
coefficient is a bound, not a point — `corr(out,cr)=0.936`, `cond(X)=23,556`). `exchange-rate.md`
*"What would falsify my headline"* #3 specifies the separating probe. It could move the ≤ +16% bound
to a point; **it cannot revive +50%**, which both fits exclude — the 68% premise fails under the
API-list hypothesis too (~28%). So this row's verdict does not depend on that question resolving.

## 6 · The residue is CURED ≠ CLOSED, and it is a known row

Three dispatches, one unchanged verdict since 2026-08-24. The mechanism is not this row's subject
matter and is already filed: `cloud-return.sh` step 8 closes a row only when the path set derived
from **the VM's own commits** content-verifies on trunk, so the one outcome that produces a spurious
re-dispatch — *the work was already done, so write nothing* — is the one outcome the closer refuses
to act on. Recorded at `docs/plans/MASTER_ENFORCING_STORE.md:192` with the honest-fix row already
minted there ("close a row whose CITED paths are on trunk, not only one whose dispatch landed
commits"), and at `docs/plans/CLOUD_OBSERVABILITY.md` §14, whose rule this file follows. Nothing new
is filed for it.

`~/.claude/autonomy/` does not exist in this container, so `cc-backlog done` writes nothing from
here and the row cannot be moved. **Because this entry is a commit, the dispatch now has a non-empty
path set, so the returner's own arm closes the row once the desk lands it** — the workaround stated
as what it is.

**Ledger replay, if the desk's return pass does not fire:**

```sh
cc-backlog done 564d151b76e5 --evidence 7bb14728a
```
