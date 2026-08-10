# cluster-P-docclf — triage vs origin/main @ cc6a30a6a62c664a1e06c799bb829f6c00b1fa57

Repo: `/Users/chrisren/Development/doc_classifier` (exists; remote `https://github.com/renchris/doc_classifier.git`).
No `CLAUDE.md` at the repo root and none under `.claude/` (only `settings.local.json`) — this project
publishes **no** ship policy and has **no `/ship` rail**, which is the single most load-bearing fact
below.

**The governing measurement: `origin/main` has not moved in 10 days.** `origin/main` = `cc6a30a6`,
committed **2026-07-30T00:28:24-07:00**, and `.git/FETCH_HEAD` is stamped **2026-08-09 12:26** — so
that is a *fresh* read, not a stale remote-tracking ref. Meanwhile the repo carries **41 local
branches and 30+ worktrees**, of which at least 8 are gate-green and unlanded. Consequence for this
triage: **subject-churn (contract step 3) is identically zero for every item**, because nothing has
landed since before most items were filed. The only available decay vectors were (a) a fix that
landed *before* 07-30 and the filer read a stale tree, and (b) a premise refutable by reading main
directly. Both fired exactly once each.

## Summary

counts: **PRUNE 1 / UPDATE 4 / KEEP 12 / MERGE 1**  (= 18)

## Verdicts

`798ab27d8116` | **PRUNE** | Remedy already on `origin/main` since **9f6d5a0d** (2026-07-21) *"feat(s6): bootstrap review cells surface the s5 winner as a proposed value"* (+ `68a04d8a`). `engine.py:709-724` now computes `proposed = _delivered_winner(...)` for non-bypass, non-SUPPLIER_NAME fields and emits `value=proposed` with `status=NeedsReview(BOOTSTRAP_UNCALIBRATED)` — verbatim the item's prescribed fix. Corroborated independently: docclf `MEMORY.md:57` marks `s6-bootstrap-nulls-every-value` **SUPERSEDED**, naming `9f6d5a0d` as what landed. Item was filed 2026-08-01 by `cc-backlog-reap` off a dead verify lane (`session-1a705246`, idle 5673s) reading a pre-07-21 tree.

`dcd894ef1cb5` | **UPDATE** | Defect verified live: `pipeline/backbone/port/preflight.py:817` — `CheckSpec(PreflightCheckId.PF_23, False, frozenset({PortVerb.REVIEW}), local_fn=check_pf23)` gates the **whole** `review` verb on `spa_assets_ok`, so `review --export-decisions` / `--migrate` demand the SPA dist they never use. **But the item's remedy is unbuildable as written**: it says "scope PF-23 to `--serve`", and `PortVerb` (preflight.py:84-90) has no `SERVE` member — the enum is FREEZE/PROBE/CALIBRATE/EXTRACT/REVIEW/EXPORT/SMOKE. The correct remedy is the pattern already in the same file: `inputs.review_migrate` (line 203) makes PF-15 **SKIP** under `review --migrate` — PF-23 needs the same sub-flag SKIP, not a new verb. Cross-ref `d57c2d8e` verified as a real commit (2026-07-21, *"fix(preflight): $0 local verbs stop gating on unset endpoint env"*) — same family, confirmed.

`10eb9e8c5d0c` | **KEEP** | Premise intact: no deploy orchestrator exists on `origin/main` — the only match for "one-click deploy" repo-wide is the gap doc itself, `docs/research/doc-classifier-100th-percentile-gap-2026-07-19.md` (present, blob `baa8fbd5`). Genuine money/auth escalation (live Azure deploy creds), correctly operator-gated. ⚠ One anchor is bad: the cited *"core commercial scope already landed 37d0e86a"* — `37d0e86a` is **not a revision in this repo** (`fatal: unknown revision`); it is probably a backlog id, not a sha. Do not treat it as landed evidence.

`bf313fdd7a3a` | **MERGE** | → canonical **`6a8df00b9b52`**. Identical subject (delete Azure RG `rg-dcl18-validate` after WORM age-out); `6a8df00b9b52` carries the fuller, correct command (the `az storage container-rm delete` step first, which `bf313fdd7a3a` omits).

`b45a6b831506` | **KEEP** | Verified on `origin/main`: `reviewapp/api/db.py:366` — `SELECT 1 FROM blind_entry WHERE cell_key = $1 AND reviewer_id = $2 LIMIT 1`. No `run_id` term, while the sibling insert path *does* write a `run_id` column (db.py ~line 360). The protocol at `reviewapp/api/cells.py:30` has the same run-free signature, so the leak is structural, not a call-site slip. 5 live callers (`decisions.py:196`, `family.py:293`, `routers/triage.py:74`, `secondkey.py:185`, + protocol).

`e3d8a8cf90a4` | **KEEP** | Verified on `origin/main`: `reviewapp/api/routers/run.py` contains **zero** occurrences of `require_role` or `Principal` (grep), while the sibling `routers/audit.py:21` imports `Principal, ReviewerRole, require_role` and gates every route (`audit.py:45,113`). `run.py`'s only `Depends` are resource-root injectors (`get_run_monitor_root`, `get_artifacts_root`, `get_audit_root`). `corpus_root` is validated by `body.corpus_root.is_dir()` (run.py:954) alone — any host path that exists passes.

`c07fb00eb9b6` | **KEEP** | Latency premise confirmed: `pipeline/backbone/cli.py:1884` still raises *"a TargetReader adapter is installed but the reconcile bridge is not wired"* — no production caller, exactly as filed. Sub-claim spot-checked and confirmed: `pipeline/s9_export/report.py:125` `render_report(report, quarantine)` takes the roster **beside** the report and its own docstring says the report carries "the HASH, not the entries" — yet nothing in the function asserts `record_hash(quarantine) == report.quarantine_ref`; the render is `_header/_counts/_dollars/_columns/_quarantine/_verdict` with no cross-check. `staged_batch_hashes` (`s9_export/loader.py:93,280`) is a tuple of `record_hash` per batch — keys, not bytes, as filed.

`1a9f3323e4d7` | **UPDATE** | **Not a defect on `origin/main` — the subject does not exist there.** `git show origin/main:pipeline/backbone/driver/stages.py | grep build_working_writer` returns nothing; the function exists only at `1ae05b9b:pipeline/backbone/driver/stages.py:565`, on the unlanded branch `wt-af8883c4cc08` (1 ahead of main). So this is a **pre-land gate on `1ae05b9b`**, not a live cleartext-PDF exposure — and the item should say so, because "strictly worse than the OCR-cache original" reads as a shipping vulnerability. The prescribed model fix `26510dd6` (*"fix(cache): encryption-at-rest keys off the storage account, not the namespace"*) is **also unlanded** (`wt-cd1ae57c1d67`, 1 ahead). Corroborated by docclf `MEMORY.md:16`: *"a copied gate copies its hole (`1ae05b9b` cloned it onto the decrypted PDF → `1a9f3323e4d7`)"*.

`6a8df00b9b52` | **KEEP** | **Live-verified today: `az group exists -n rg-dcl18-validate` → `true`.** The RG is still standing, **19 days** past its own 2026-07-21 age-out condition. The item's command is runnable now, unmodified. This is the one item in the slice with a positive live-infrastructure measurement rather than a code read.

`16319f4234a3` | **UPDATE** | Core defect real, **but the count is wrong: two sites, not three.** Confirmed broken — (1) `pipeline/backbone/port/init.py:208` `parsed = json.loads(proc.stdout)` sits after `except (OSError, subprocess.SubprocessError): return {}` at line 206, so `JSONDecodeError` escapes; (2) `pipeline/backbone/port/azure_probes_client.py:900` `_az_json`, identical shape. Already correct — (3) `azure_probes_client.py:814` has `except json.JSONDecodeError: return {}` and a docstring explaining it, so it must be dropped from the item. Also: **no `.decode(` sites exist** — both subprocess calls use `text=True`, so decoding happens *inside* `subprocess.run` (i.e. inside the try); `UnicodeDecodeError` still escapes, but because the handler doesn't catch `ValueError`, not because the decode "sits OUTSIDE the try". Fix the mechanism sentence when rewriting.

`d44857742d3a` | **KEEP** | Every stated fact re-verified today. `wt-90eed49dd55c` = `d3573e61`, **2 ahead** of `origin/main`, `merge-base --is-ancestor` = **no**. `git merge-base --is-ancestor 211c94a5 d3573e61` = **true** — the peer's S1 body-identity commit does ride along exactly as warned, and `211c94a5` is itself unlanded (`wt-d30bf71a94fb`, 1 ahead). The "second commit you did not ask for" caveat still holds verbatim.

`8c7f7ae4ee4d` | **KEEP** | All three ancestry claims in the CORRECTED-2026-08-08 `needs` re-verified: `git merge-base --is-ancestor ed16f861 e601a10e` = **true**, `... 0e9215b3 e601a10e` = **true**. Branch states today: `wt-35cae65a8d2d`=`e601a10e` (3 ahead), `wt-769c22b99fec`=`e6b02396` (6 ahead), `wt-f22f37caa892`=`ed16f861` (2 ahead), `wt-cb9ab22e7b12`=`0e9215b3` (1 ahead) — **none merged into main**. Nothing has decayed; the correction still names the right target.

`38de29ec5e59` | **KEEP** | Verified on `origin/main`. `pipeline/backbone/port/build.py:126-137` `_stage_uv` runs `pip download uv==<UV_VERSION> --no-deps --only-binary=:all: <platform_args> -d <scratch>` — **no `--require-hashes`, no `--index-url`**. The wheelhouse fetch at `build.py:480-492` **does** pass `--require-hashes -r requirements.lock`. The `_stage_uv` docstring (lines 118-122) claims it is "fetched with the same `pip download --only-binary` mechanism as the wheelhouse" and that "the binary's own sha256 joins PACKAGE_MANIFEST.json" — i.e. the docstring itself states the self-referential property the item flags: the packager *records* the sha it just downloaded rather than verifying it against a pin.

`ce7651b02a17` | **KEEP** | Verified on `origin/main`: `reviewapp/api/auth.py:73` — `jwt.PyJWKClient(settings.jwks_url, cache_keys=True).get_signing_key_from_jwt(...)` is constructed **inline, per token**, in the verification path. `cache_keys=True` caches only within that throwaway instance, so it buys nothing across requests and every presented token (including rejected ones) can drive a JWKS fetch. Single site; the PoC's 4-fetches-from-2-rejected-tokens shape is consistent with this code.

`35cae65a8d2d` | **KEEP** | **Its own DoD falsifier re-run today and still red**: `git show origin/main:reviewapp/api/routers/run.py | grep -c require_loopback_client` = **0**. Also 0 for `reviewapp/api/routers/corpus.py` and `routers/azure_status.py`. `origin/main` still serves all three loopback holes, `POST /api/run/start` included. `run.py` defines the two routers as described (`router = APIRouter()` line 70 carrying `/api/capabilities`, `_run = APIRouter(prefix="/api/run")` line 76). The refusal to mark this done was correct and remains correct.

`24299f47405f` | **UPDATE** | Premise holds, **number is stale**. `~/.claude/projects/-Users-chrisren-Development-doc-classifier/memory/MEMORY.md` is now **21,389 B (20.9 KB)**, not the filed 20.3 KB — it grew ~1 KB in a day and has **~3.6 KB headroom** against the ~24,985 B loader limit. It has **not** tripped yet, so "it will silently stop loading" is a forecast, not a current state; say so. All three named compaction candidates verified still present and still so-marked: `extraction-works-s6-discards-it` (HALF-SUPERSEDED, line 14), `fable-frontier-findings-2026-07-18` (queue CLOSED, line 18), `s6-bootstrap-nulls-every-value` (SUPERSEDED, line 57). ⚠ Note the path: the live index is under `~/.claude/projects/-Users-chrisren-Development-**doc-classifier**/` (hyphen), not `doc_classifier`.

`39d8431abae5` | **KEEP** | **Its own DoD falsifier re-run today and still red**: `git show origin/main:reviewapp/api/routers/corpus.py | grep -c loopback` = **0** (DoD requires 8). The arbitrary-directory census is still what main serves. `0e9215b3` remains contained by no remote ref — `wt-cb9ab22e7b12` and `wt-39d8431abae5` both point at it, both 1 ahead, neither an ancestor of `origin/main`. The stranding this item was filed to flag is 10 days deeper than when it was filed.

`7bc597f698a7` | **KEEP** | Both sides verified on `origin/main`: `tests/fixtures/gen/scenarios.py:2318` authors `native_text_coverage=tuple(1.0 if page.born_digital else 0.0 for page in file.pages)`; `pipeline/s1_substrate/native_probe.py:81` `probe_native_text_coverage(pdf_bytes, thr)` measures real glyph density. Nothing asserts agreement — and the mitigating guard the item cites (`test_fixture_intake_mirror.py`, "excludes the field BY NAME") **does not exist on `origin/main`** either: `af0c3788` (2026-08-08, *"fix(fixtures): the intake ground truth the §4 gate never agreed with"*) sits on unlanded `wt-3f3d0dfd9d55`. So the divergence is unguarded *and* undocumented on trunk. The open question (which side is right) is genuinely open and is the reason this can't be closed by a one-liner.

## Master item(s)

Three, and the split is a real dependency ordering, not a taxonomy: **M-P-1 is a hard prerequisite
for M-P-2 and M-P-3.** Any fix written for the latter two today joins a 20-branch pile that has not
moved in 10 days — which is precisely the state 9 of these 18 items are already stuck in.

---

### M-P-1 — doc_classifier has no agent-executable rail for its terminal actions, so 10 days of finished, gate-green work is stranded off trunk

**Encompasses:** `39d8431abae5`, `35cae65a8d2d`, `8c7f7ae4ee4d`, `d44857742d3a`, `6a8df00b9b52`
(absorbing `bf313fdd7a3a`), `24299f47405f`, `10eb9e8c5d0c`

**Why one effort:** every one of these is *agent-side complete and blocked on an action this repo
gives no agent a rail to perform* — merging to trunk, deleting a live Azure resource group,
approving a memory compaction, authorizing deploy credentials. The shared root cause is structural,
not per-item: this repo publishes no `CLAUDE.md`, no ship policy, and no `/ship` command, so the
global "auto-land by default" rule has nothing to actuate. The measurement that makes it one effort
rather than seven chores: `origin/main` is frozen at `cc6a30a6` (2026-07-30) against **41 branches
and 30+ worktrees**, and the *same* dispatcher string — *"persistent thrash — 2 fast claim→reopen
cycles (spawn-fail / land-conflict rebase-exit-5); the worker cannot land"* — appears on **9 of 18**
items in this slice, all restamped **today**. The backlog is not stalled; it is *churning*, spending
worker dispatches to re-derive fixes that then cannot land.

**Impact, argued from evidence:**
- **It is the gate on the other two masters.** 5 further KEEP/UPDATE items in this slice describe
  code that can only be fixed by landing something. Closing M-P-1 converts 12 blocked items into
  ordinary work.
- **Three loopback holes are live on trunk right now**, with fixes written, tested (`make ci` 4580
  passed / 94.93% cov per the item), and sitting on a branch. `POST /api/run/start` on `origin/main`
  has neither an authz dependency (`e3d8a8cf90a4`) nor a loopback gate (`35cae65a8d2d`) — an
  unauthenticated remote caller spawns the `run-all` spine. One `--ff-only` merge retires all three.
- **It retires the largest duplicate cluster in the slice.** `39d8431abae5`, `35cae65a8d2d` and
  `8c7f7ae4ee4d` are three rows carrying the *same corrected merge command*; the correction has been
  re-issued **three times** (the `needs` fields say so), each time because a newer sibling branch
  stranded the previous target. That re-correction cost is recurring and unbounded until a land
  happens.
- **It touches an enforcing store**: `origin/main` *is* what the deploy package is built from.
- One live-infrastructure cost is accruing: `rg-dcl18-validate` **exists today**, 19 days past its
  own deletion condition.

**DoD:** `origin/main` carries `e601a10e` (all three loopback fixes) and `e6b02396`
(untrusted-input scan fixes), `make ci` green on the merge result and pushed; `d3573e61` landed or
its ride-along `211c94a5` explicitly ratified/rejected; `rg-dcl18-validate` gone
(`az group exists` → `false`); docclf `MEMORY.md` compacted with human approval; the
deploy-orchestrator scope decision recorded (scope + creds, or an explicit park with a reason).
And — the durable half — **a project `CLAUDE.md` in `doc_classifier` stating its ship policy**, so
the next agent is not structurally blind to it.

**Falsifier:**
```
cd ~/Development/doc_classifier && git fetch -q origin && [ "$(git show origin/main:reviewapp/api/routers/corpus.py | grep -c loopback)" -ge 8 ] && [ "$(git show origin/main:reviewapp/api/routers/run.py | grep -c require_loopback_client)" -ge 1 ] && git merge-base --is-ancestor e6b02396 origin/main && [ "$(az group exists -n rg-dcl18-validate)" = "false" ]
```

**First move:** re-verify the merge target has not been stranded a **fourth** time — enumerate every
`wt-*` branch ahead of `origin/main` (`git for-each-ref refs/heads --format='%(refname:short)'` +
`git rev-list --count origin/main..<b>`) and pick the branch that is a strict ff-descendant of the
most others, *before* running any merge. As of today that is still `wt-35cae65a8d2d` (`e601a10e`),
verified. This step is not ceremony: it is exactly the check whose absence caused the three prior
re-corrections.

**Order:** 1. `35cae65a8d2d` / `39d8431abae5` / `8c7f7ae4ee4d` (one ff-merge lands all three — do
these together or the next one strands) → 2. `d44857742d3a` (separate branch; decide the `211c94a5`
ride-along explicitly) → 3. `6a8df00b9b52` (+`bf313fdd7a3a`; independent, runnable now, cheapest —
can go first if you want a win) → 4. write `doc_classifier/CLAUDE.md` with the ship policy →
5. `24299f47405f` (`/compact-memory`, human-gated) → 6. `10eb9e8c5d0c` (operator scope decision;
the weakest member of this grouping — it is a 2-4 day build, not a terminal action, and the lead may
prefer to split it out).

---

### M-P-2 — close the untrusted-input trust-boundary findings the `71258c80fce2` scan family raised across the reviewapp API and the deploy port

**Encompasses:** `e3d8a8cf90a4`, `ce7651b02a17`, `38de29ec5e59`, `16319f4234a3`, `1a9f3323e4d7`

**Why one effort:** four of the five carry `source: 71258c80fce2` — one scan, one surface. The shared
root cause is the repo's own most-named defect (docclf `MEMORY.md:16`,
*defined-not-wired-production-reachability*, **wrong-AXIS** sub-shape): a control exists, but the
thing it keys on is not the thing that decides safety. `run.py` keys privileged spawn on a resource
root instead of a principal; `auth.py` keys JWKS caching on an object that dies each request;
`_stage_uv` keys integrity on a recorded sha instead of a required hash; the az parsers key their
handler on `SubprocessError` while the escaping exception is a `ValueError`; `build_working_writer`
keys a cleartext-vs-encrypted sink on a *provenance* namespace instead of a *capability*. Fixing them
one-by-one re-learns the same lesson five times; fixing them as one axis-separation pass does not.

**Impact:**
- Highest-severity live item in the whole slice sits here: `POST /api/run/start` on trunk spawns a
  subprocess pipeline for an unauthenticated caller over an unvalidated host path.
- `38de29ec5e59` is supply-chain: the unhashed `uv` binary is what `bootstrap.sh` **executes** on the
  operator's deploy box, and `verify-package.sh` cannot catch a poisoned one because it verifies
  against a sha the packager itself recorded.
- `1a9f3323e4d7` is the cheapest possible win **if caught before landing** and an incident **if
  caught after** — it writes decrypted, e-signature-flattened customer PDFs to local disk. Its
  window closes the moment M-P-1 merges `1ae05b9b`.

**DoD:** `run.py`'s two routers carry both a principal dependency and `require_loopback_client`,
pinned by a remote-client test; `PyJWKClient` is module-scoped/cached across requests; `_stage_uv`
fetches under `--require-hashes` against a pin the packager does not itself author; both az/git parse
sites catch `ValueError` (or move the parse inside the try) and degrade to PF-17 rather than
tracebacking; `build_working_writer` selects its sink from `blob_account_url`, not
`CalibratorNamespace`, per `26510dd6`'s axis separation. `make ci` green; landed on `origin/main`.

**Falsifier:**
```
cd ~/Development/doc_classifier && git fetch -q origin && git show origin/main:reviewapp/api/routers/run.py | grep -q require_role && git show origin/main:pipeline/backbone/port/build.py | sed -n '116,140p' | grep -q -- --require-hashes && git show origin/main:reviewapp/api/auth.py | grep -qv 'jwt.PyJWKClient(settings.jwks_url, cache_keys=True).get_signing_key_from_jwt'
```

**First move:** do `1a9f3323e4d7` **first and out of order** — it is a pre-land gate on an unlanded
branch, so it must be resolved either just before or as part of M-P-1's merge of `1ae05b9b`;
after that merge it stops being a cheap branch edit and becomes a trunk vulnerability.
Concretely: `git show 1ae05b9b:pipeline/backbone/driver/stages.py | sed -n '560,600p'` and port
`26510dd6`'s axis separation onto it.

**Order:** 1. `1a9f3323e4d7` (window closes at M-P-1's merge) → 2. `e3d8a8cf90a4` (same file and same
test as `35cae65a8d2d`'s fix — do them in one diff or they conflict) → 3. `ce7651b02a17` →
4. `38de29ec5e59` → 5. `16319f4234a3` (rewrite the item first: two sites, not three).

---

### M-P-3 — make the latent S9/review-store/fixture contracts agree with what the code actually computes, before the wiring makes the disagreement live

**Encompasses:** `c07fb00eb9b6`, `b45a6b831506`, `7bc597f698a7`, `dcd894ef1cb5`

**Why one effort:** all four are the *latent* form of the same failure — an artifact, a gate, or a
ground truth asserts a property nothing verifies, and each is benign only because the path that would
expose it is not yet reached. `c07fb00eb9b6` is unwired until B22 (`cli.py:1884` says so in its own
error string); `b45a6b831506` is benign only at single-run scale; `7bc597f698a7` diverges on 2
scenarios that no assertion compares; `dcd894ef1cb5` gates a `$0` verb on an asset it never reads.
Each becomes a real defect at the moment of a wiring change, and they will all be wired by the same
B22 handoff-package work. This is the *latent* half of the same recurring defect M-P-2 addresses in
its *live* half — genuinely disjoint from M-P-2 in when it bites, not in what it is.

**Impact:** lower urgency than M-P-1/M-P-2 and it should be sequenced that way — but
`c07fb00eb9b6` alone bundles five independent sign-off defects in the artifact that **signs Gate 4**,
including a report that renders a quarantine roster it never proves matches its own
`quarantine_ref`. A wrong GO on a money-reconciliation gate is the worst-consequence item in the
slice even though it is the least urgent. `dcd894ef1cb5` is the cheapest of the four and directly
unblocks WORM `--export-decisions` on a machine with no SPA build.

**DoD:** `render_report` asserts `record_hash(quarantine) == report.quarantine_ref`; the dollar
control total excludes quarantined families; a MERGEd quarantined family cannot sign GO; an
unattributable CLM failure gets a real `family_id`; `staged_batch_hashes` pins bytes; `has_blind_entry`
is run-scoped at the protocol *and* both implementations (`cells.py:30`, `db.py:366`) with all 5
call sites updated; the `native_text_coverage` divergence is adjudicated (probe right → fix the
authored ground truth; renderers right → fix the renderers) and pinned by an assertion; PF-23 SKIPs
under the `$0` review sub-verbs via the `review_migrate` pattern.

**Falsifier:**
```
cd ~/Development/doc_classifier && git fetch -q origin && git show origin/main:pipeline/s9_export/report.py | grep -q quarantine_ref && git show origin/main:reviewapp/api/db.py | grep -A6 'async def has_blind_entry' | grep -q run_id && git show origin/main:pipeline/backbone/port/preflight.py | grep -q 'PF_23.*review_migrate\|review_export_decisions'
```

**First move:** `dcd894ef1cb5`, because its remedy has to be *redesigned* before anyone can execute
it (the filed remedy names a `--serve` verb that does not exist) and the replacement pattern is
already in the file at `preflight.py:203` — read that, then `preflight.py:817` and the
`ProbeInputs` field block at 169-203.

**Order:** 1. `dcd894ef1cb5` (cheapest; remedy needs a rewrite first) → 2. `b45a6b831506` (contained:
one SQL predicate + one protocol signature + 5 call sites) → 3. `7bc597f698a7` (needs a *decision*
on which side is right — do not let it block the other three; `af0c3788` on `wt-3f3d0dfd9d55` is
prior art) → 4. `c07fb00eb9b6` (largest; 5 sub-defects; schedule against the B22 wiring, not before).

## Notes for the lead

1. **The single fact that should change your synthesis: `doc_classifier`'s `origin/main` has not
   moved since 2026-07-30 and the repo has no ship rail and no `CLAUDE.md`.** Every other cluster's
   staleness assumption ("items decay because trunk moved") is *inverted* here — nothing decayed
   because nothing landed. If other clusters found many PRUNEs and this one found one, that
   asymmetry is real and explainable, not a difference in triage rigor.

2. **Collapse the landing rows before you apply anything.** `39d8431abae5`, `35cae65a8d2d` and
   `8c7f7ae4ee4d` are three items carrying one merge command; their `needs` fields have been
   re-corrected **three times**, each correction triggered by a *newer* branch stranding the
   previous target. That is a self-generating item stream: it will emit a fourth correction the
   moment another `wt-*` branch is created. Collapse to one canonical row (`35cae65a8d2d` has the
   most complete `needs`) — this is a cross-cluster pattern worth checking for elsewhere.

3. **A dispatcher-level pathology, probably not doc_classifier-specific.** The exact string
   *"persistent thrash — 2 fast claim→reopen cycles (spawn-fail / land-conflict rebase-exit-5); the
   worker cannot land"* is on **9 of my 18** items, all restamped 2026-08-09. If it appears in other
   clusters too, it is **one bug** (workers dispatched into a repo whose land path cannot succeed),
   not N independent stuck items — and re-dispatching them is pure loss until M-P-1 closes. Worth a
   cross-cluster grep before any bulk `unblock`.

4. **Two items carry anchors that do not resolve — do not treat them as evidence.**
   `10eb9e8c5d0c` cites *"core commercial scope already landed 37d0e86a"*; `37d0e86a` is not a
   revision in this repo. `24299f47405f`'s memory path is under
   `…/-Users-chrisren-Development-**doc-classifier**/` (hyphen), which is *not* the repo directory
   name (`doc_classifier`, underscore) — a lead scripting the compaction against the underscore path
   will silently target nothing.

5. **One item is genuinely time-boxed and gets more expensive on a schedule you control.**
   `1a9f3323e4d7` is currently a cheap edit on an unlanded branch. The moment M-P-1 merges
   `1ae05b9b`, it becomes a trunk vulnerability that writes decrypted customer PDFs to local disk.
   **Sequence it before or inside that merge**, not after — this is the one ordering constraint that
   crosses my master items.

6. **`6a8df00b9b52` is the only item in the slice backed by a live infrastructure measurement**
   (`az group exists -n rg-dcl18-validate` → `true`, run today). It is one command, costs nothing,
   and is 19 days overdue. If you want a zero-risk first action out of this cluster, it is that one.

7. **Read-only compliance:** no file in any repo was edited, no `cc-backlog` verb was run, nothing
   was committed, fetched-into, or landed. The only non-git command was a read-only
   `az group exists`. `git fetch` was deliberately **not** run — `.git/FETCH_HEAD` was already
   stamped today (2026-08-09 12:26), so `origin/main` was fresh without mutating any ref.
