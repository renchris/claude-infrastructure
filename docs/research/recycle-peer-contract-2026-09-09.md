# A `--recycle` inherits a fired peer's self-retire contract — the design call, and the half of the filing that was wrong

**Item:** cc-backlog `fe740e799fd5` (filed 2026-08-10, driven 2026-09-09).
**Verdict:** premise **MIXED** — one arm confirmed end-to-end, the other's *fact* true and its
*consequence* refuted. Both are fixed; the refutation is recorded here because acting on the filed
wording would have produced the wrong repair for the same-dir case.

## 1. What the item claimed, and what is actually true

| Filed claim | Verdict | Measured |
|---|---|---|
| `WANT_SELF_RETIRE` is forced 0 for any recycle, so a recycled pane is never (re)stamped | **fact CONFIRMED** (`[ "$SELF_RETIRE" = 1 ] && [ "$RECYCLE" = 0 ] && WANT_SELF_RETIRE=1`) | — |
| …therefore a recycled peer "can no longer self-close" | **REFUTED for the same-dir form** | the real self-close origin gate, driven at the stamp's own cwd: **rc 0**, no refusal |
| A RELOCATING recycle (`--recycle --worktree/--cwd`) moves `LAUNCH_DIR` while the pane keeps its id, so the stamp reads `stale` → `origin` → the close is refused | **CONFIRMED end-to-end** | same stamp, same pane, read from the new dir: **rc 2**, `the fired-peer stamp for pane X belongs to a DIFFERENT session` |

Nothing in the recycle path touches the stamp (no `closedAt` writer is reachable from it), so a
**same-dir** recycle leaves a `valid` stamp in place and self-close is *already* permitted. The
filed net ("can no longer self-close") is therefore true of the relocating form **only**.

**What the same-dir form really loses is the CONTRACT TEXT.** With `WANT_SELF_RETIRE=0` the
successor's brief carries no self-retire trailer, so it is never told it is a fired peer that owes a
ping and a close — it finishes and idles, which is the deference defect the trailer exists to
prevent. Compounding it: `fired_contract_in_my_brief` (the `c163f42390a3` repair path) reads the
FIRST USER MESSAGE, so for a recycled peer the repair is structurally unreachable — the recycle
payload carries neither token.

Why this distinction is load-bearing rather than pedantic: a repair aimed at the filed wording
(re-stamp every recycle via `mark_fired_peer`) would **re-mint** a record this pane already holds and
lose the original fire's `originator`, `notifyBack` (the address `sc_announce_before_retire` enforces
the ping to), `marker`, `engagedAt` and `engageLatencyS`. The same-dir case needed the brief, not the
stamp; the relocating case needed the stamp *migrated*, not rewritten.

## 2. Supersession adjudicated — neither sibling discharges it

* **`c163f42390a3`** (stamp repair) runs **only** on tenancy `absent`, after adoption has failed, and
  its own header states it must never reach past a `stale`/`spent` stamp. The relocating recycle
  produces `stale`. Not covered.
* **`fd5196ac31ef`** (`oi_marker_inbound`) replaced the bare marker grep on `oi_origin_class`'s two
  *proof* arms. The `stale) printf 'origin'` mapping is untouched, and self-close keeps its own
  stricter arms (`origin-identity.sh`: *"Do NOT reuse this mapping for self-close"*). Not covered.

Tree was **trunk** (`HEAD..origin/main` = 0) and the dispatcher blob equalled
`origin/main:bin/cc-dispatch`, so "landed" and "live" coincide for this reading.

## 3. The design call: INHERIT, and only on positive proof — conviction 93%

The item was right that this needed deciding rather than assuming. It is **inherit**, and it is not a
coin-flip between two defensible options:

1. **The house already answered the identical question for the other live contract a recycled pane
   holds.** `inherit_recycle_goal` re-arms the predecessor's live `/goal` on the successor, with
   `CC_RECYCLE_GOAL_INHERIT` defaulting to 1. Self-retire is the same shape — an obligation held by
   the **pane**, not by whichever process was running in it. Two opposite answers to one question in
   one script is drift.
2. **Dropping it does not merely idle a pane, it strands a lead.** The originator's custody debt
   (`bin/cc-custody`) is discharged by this pane's self-close and by nothing else, so a dropped
   contract makes the originator's `✅` certificate mechanically unreachable for good.
3. **`--recycle` is the DEFAULT succession** (`CLAUDE.md` § Context Stewardship: *"Reach for Recycle
   first"*), so dropping the contract there retires the feature on its main road — which is the
   pane-427 cost one item upstream.

**Conferred only on tenancy `valid`.** `absent` means this pane never held a contract and a recycle
may not mint one (an operator's own pane recycling into a worktree must not become self-retiring);
`stale`/`spent` mean a stamp for this id exists and says something, and reaching past it would hand
one pane two contradictory contracts. The **remote** form (`--source-pane`) abstains: there `$PWD` is
the caller's cwd, not the target pane's, so the tenancy compare would be asking about the wrong
directory.

Residual 7%: nobody has measured how often a *relocating* recycle is used on a genuine peer, so the
`valid`-only gate could be conferring on a population of size ~0. That bounds the value, not the
correctness — and the negative direction (an origin pane gaining a contract) is pinned by test.

## 4. The fix

* `hf_recycle_inherits_peer` — the gate. `RCY_INHERIT_PEER` is derived once, after `SID` is verified.
* `hf_migrate_peer_stamp` — moves the stamp's `cwd` to the new dir, **additively** (`recycledFrom` /
  `recycledAt`, exactly as adoption's `adoptedFrom` / `adoptedAt`), keeping every field the original
  fire recorded, and repoints the by-cwd index. Called once, gated `RCY_INHERIT_PEER=1 &&
  RECYCLE_RELOC=1 && DRY=0`, at the `LAUNCH_DIR` block — the same site the succession-lineage edge
  picks, and for the same stated reason.
* `SELF_RETIRE_TRAILER` — a **new** flag for the brief. `WANT_SELF_RETIRE` is left untouched on
  purpose: four other sites read it (two `mark_fired_peer` call sites that would re-mint, plus the
  `handoffs.jsonl` class label), and a recycle needs none of them.

The **old** by-cwd pointer is deliberately left in place: every consumer re-validates a pointer
against the pane-keyed record (`find_open_stamp_for_cwd` re-reads `.cwd` and falls through to the
scan), so a leftover costs a scan and never a verdict — while deleting it could race a legitimate
later peer's key under last-writer-wins.

## 5. Mutant power, measured — and one case that is an equivalence guard

`tests/handoff-recycle-peer-contract.bats`, 9 cases. Seven mutants run against it:

| Mutant | Reds |
|---|---|
| inherit on ANY tenancy state, not just `valid` | 3 (cases 4, 5, 7) |
| re-mint the stamp instead of migrating (drops `originator`/`notifyBack`) | 1 (case 3) |
| naive `jq -n` mint | 1 (case 3) |
| call site loses the `RECYCLE_RELOC` guard | 1 (case 8) |
| trailer gated on `--recycle` alone, ignoring the stamp | 1 (case 7) |
| trailer half deleted (trunk behaviour) | 1 (case 9) |
| migration call deleted (trunk behaviour) | 1 (case 8) |

**Honest limit.** Case 4's *never-mint* assertion is an **equivalence guard**, not a red-proof: the
property is held by two redundant structural facts (the `-s` source guard *and* a `. +` transform
that cannot run without an input file), so no single-guard mutant reaches it — dropping the `-s`
guard alone leaves `jq` failing on a missing file (**reds=0**), and rewriting the transform as a
`jq -n` mint alone is stopped by the `-s` guard. Only removing both mints a stamp. Case 4's
red-proof half is its *gate* assertion, which the first mutant reddens.

## 6. A hermeticity hole this exposed in a neighbouring suite

`tests/notify-back.bats` pinned `TMPDIR` and the capacity gates but **not** `CC_FIRED_DIR`, whose
default is `$HOME/.claude/cc-fired`. Once `--recycle` began consulting that store, its case 14
(*"--recycle: self-retire AND back-channel auto-excluded"*) went red — and the subject was right:
`verify_self_pane` resolves `$SID` to the **real** pane rather than the `$ITERM_SESSION_ID` the case
passes in, and the session running bats was itself a dispatched peer in that cwd, so the tenancy read
`valid` off a genuine live stamp. The suite was executing correct logic over the operator's live
state — the `unfixtured-sensor-executes-the-deployed-subject` class, and the reason it presented as a
defect in new code. Fixed by pinning `CC_FIRED_DIR`; 17/17.

Generalisable: a suite that pins `TMPDIR`, `HOME` and three explicit dirs is still unfixtured on
every store whose default resolves outside them, and adding a **new reader** of such a store is what
converts a latent hole into a red — so when a change makes an untouched suite fail, ask which store
it never pinned before assuming the change is wrong.

## 7. Dropped, named

The stamp's `<pane>.prompt` sidecar (cc-recover-safeguard's brief source) still holds the ORIGINAL
fire's brief after a recycle, so a safeguard recovery would re-fire work already done. Pre-existing
and orthogonal — this change neither creates nor worsens it — and the failure mode is a recoverable
over-do, not a loss. Not filed: it fails the FILED test (no impossibility class).
