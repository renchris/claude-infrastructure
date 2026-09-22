# Cloudflare security-audit-skill vs codex-security — matched-scope A/B on `hooks/` @ dc12c8db

**Verdict: on this repo's `hooks/` surface cloudflare/security-audit-skill is ADDITIVE over
codex-security, not redundant — it independently re-found both of codex's findings while blind to
them, added five further independently-verified defect classes (four of them on surfaces codex's
sealed ledger had marked `no_issue_found`), and refuted one of codex's coverage claims outright —
but it bought that at ~12× the agent cost, and on a host without an OS sandbox it cannot reach
`confirmed` at all, so it is additive as a HUNTER and strictly weaker than codex as a CONFIRMER.**

Run date 2026-09-21/22. Treatment arm artifacts:
`~/security-audit-skill/claude-infrastructure-hooks-dc12c8db/run-1/`.
Control arm: `docs/research/codex-security-scans/claude-infrastructure/dc12c8db_20260729T053818Z/`.

## Experiment design and controls

One variable: the tool. Same repo, same commit `dc12c8db`, same scope `hooks/`.

- **Source parity verified by content, not by sha.** `git archive dc12c8db hooks/` re-extracted into
  a temp dir and `diff -r`'d against the audited snapshot → **0 differences**; git tree hash
  `e56658861fd735ec06be51d3aeaaf9eede973910`. No worktree was created for the target (a worktree
  add/remove can set `core.bare=true` on the shared checkout, and this checkout is the live layer's
  symlink source).
- **Scope parity, with one real difference.** The snapshot holds 69 `.sh` files / 10,459 lines,
  matching codex's recorded 69 files / 10,459 lines exactly. But codex's manifest sets
  `excludePaths: ["hooks/tests/"]` ("Test fixtures, not executed by the harness as a hook"), while
  the cloudflare run let hunters read `hooks/tests/validate-bash.test.sh`. The arms are therefore
  **not byte-identical in scope**; cloudflare saw slightly more, and several of its hunters used the
  test file as evidence of *intended* behaviour. This favours cloudflare marginally and is disclosed
  rather than adjusted for.
- **Control arm seal verified.** Both `findings.json` and `coverage.json` hash-match
  `scan-manifest.json` (`3580e11c…`, `a2f36c3c…`). The bundle was not opened until after the
  treatment arm's hunting and validation were complete.
- **Arm sealing.** No codex finding entered any agent prompt. All 40 ledger units carry
  `prior_status: "none"`; `architecture.md` §7 records the codex bundle as an *incompatible* ledger
  contributing no exclusions and no priority input, per RECONNAISSANCE.md's "record missing or
  incompatible ledgers instead of treating them as empty coverage."
- **The one confound, stated plainly.** The *parent* (me) was told codex's two finding shapes before
  the run, because measurement 2 cannot be posed without naming them. Hunters, critics and verifiers
  were blind; parent-side **unit seeding** was not. Seeding plausibly tilted toward denylist/allowlist
  and deployment units. Every unit does trace to a boundary one of the four blind recon agents named,
  but **measurement 2 is the weakest of the five** and should be read with this attached.

### Execution constraint — the skill's own behaviour, and the decisive asymmetry
SKILL.md "Universal execution safety" forbids running target code without an OS-enforced sandbox
providing *all* of: no external network, empty allowlisted env, read-only target, scratch-only
writes, and explicit CPU/memory/process/file-size/disk/wall-clock limits. Recon established from
source that none exists here: no `sandbox-exec`/Seatbelt profile, no `unshare`, no `ulimit`, no
launchd `Soft/HardResourceLimits` anywhere in the repo; test isolation is `HOME`/`TMPDIR` env
scoping only. No scratch-promotion mechanism exists either (no `O_NOFOLLOW`/`O_EXCL`/`openat`).

**Consequence, and it is structural rather than incidental:** the skill reserves `confirmed` for a
candidate with "a bounded local OBSERVED result". With no sandbox, **no candidate can reach
`confirmed` by construction.** A confirmed-count of 0 is the protocol working, not the code being
clean. Codex, by contrast, *executed the hook* — its finding 1 confidence rationale reads "Bypass
reproduced by feeding crafted payloads directly to the hook and reading the emitted
permissionDecision; the deny/ask/none split is observed, not inferred," and its finding 2 verified
`/tmp` permissions on the live host. **That is the single largest quality difference between the
arms, and it runs in codex's favour.** Note the sharp edge: `hooks/tests/validate-bash.test.sh` and
21 matching `tests/*.bats` exist, are offline, feed synthetic JSON on stdin and assert on stdout —
exactly the "existing unit test" the skill names as its preferred bounded check — and the skill
still forbids running them, because its gate is on the SANDBOX, not on the check's riskiness.

---

## 1. Finding overlap

| Defect (plain English) | codex | cloudflare | verdict |
|---|---|---|---|
| A catastrophic-command denylist keyed on one literal flag spelling, so an equivalent spelling of the same destructive command clears it | **found** (F1, medium, CVSS 5.5, reproduced by execution) | **found** — verified `needs_validation` | **both-found** |
| A notification hook writing its log and lock to fixed world-writable `/tmp` paths that a symlink can redirect | **found** (F2, low, CVSS 3.3) | **found, but dispositioned as HARDENING not a finding** | **both-found, classified differently** |
| Model-authored `tool_input` interpolated unescaped into a hook's own deny verdict JSON, letting the gated principal rewrite the gate's verdict | not found — codex marked this surface `no_issue_found` | **found** — verified `needs_validation` | **cloudflare-only** |
| A transcript path spliced into a `python3 -c` program text, reachable from an agent-creatable directory name, re-entered every 60s by a launchd job outside every PreToolUse gate | not found | **found** — verified `needs_validation` | **cloudflare-only** |
| An operator-only `git reset --hard` auto-allow armed by nothing but the existence of a file the agent can create | not found | **found** — verified `needs_validation` | **cloudflare-only** |
| A model-authored basename becoming the `find` GLOB PATTERN of the backup pruner, widening a delete beyond one file's backups | not found — codex marked `surface_path_handling` `no_issue_found` on this very file | **found** — verified `needs_validation` | **cloudflare-only** |
| The only deny-emitting hook in the Bash chain parsing its input with an unguarded `jq`, so any jq failure silently voids the whole deny list | not found | **found** — verified `needs_validation` | **cloudflare-only** |
| Bundled/short-option and clause-split variants beyond the `rm` case (`git add -Af`, `git commit -an`, `true ;git commit --no-verify`, quote-spliced `--no-ver''ify`) | partially — codex's F1 covers the `rm` family only | **found**, three separate verified root causes | **cloudflare-broader** |

**Counts.** Of cloudflare's 8 verified-surviving records: **3** are the codex-F1 class (the same
root cause, at the same lines, plus two adjacent spelling/parsing variants codex did not report) and
**5** are cloudflare-only. Codex F2 was additionally detected by cloudflare but dispositioned as
hardening rather than a finding. So: **both-found 2** defect classes · **cloudflare-only 5** verified
**+ 46 further unvalidated candidates** · **codex-only 0**. No codex finding was missed by cloudflare.
Four of the five cloudflare-only classes fall on surfaces codex's ledger positively dispositioned as
`no_issue_found` (`surface_json_decision_integrity`, `surface_path_handling`, `surface_command_injection`)
rather than on surfaces it never enumerated.

## 2. The codex pair specifically — did cloudflare's roster reach them?

**Yes, both, and blind.**

**Codex F1 — the flag-spelling denylist bypass.** Reached by `hunter-bash-gates-core` via the ordinary
`ATTACK-CLASSES.md#Access control` and `#Injection` blocks, plus `AI-AND-LLM.md#Tool-argument
injection into a downstream sink`. It landed on the *same file and the same line*: codex cites
`hooks/validate-bash.sh:94` and `:195`; cloudflare's verified record cites `hooks/validate-bash.sh:94`,
`:155`, `:174` and `hooks/lib/is-true-flag.sh:186`, and its title is "Bundled short options are never
decomposed, so -Af, -fA, -an, **-Rf and -rvf** spellings clear the git-add-force,
git-commit-no-verify and **rm** gates". Both arms independently proposed the *same remediation
direction* — normalise to argv using the repo's own `lib/is-true-flag.sh` rather than pattern-match
raw text. Cloudflare additionally found two adjacent root causes codex did not report: a layer-1
literal-substring short-circuit defeated by ordinary shell quote-splicing, and a clause splitter that
misses an unspaced separator. Codex's version is narrower but **executed and severity-scored**;
cloudflare's is broader but unexecuted.

**Codex F2 — the `/tmp` symlink issue in `notify.sh`.** Reached by `hunter-exec-supply-chain`, which
recorded, verbatim: *"hooks/notify.sh:35 and :39 use fixed, predictable paths in the shared temp
directory … with no no-follow open, so a pre-planted symlink at either name redirects a write made
with the operator's privileges."* Same file, same two lines, same mechanism, same remediation
(`$TMPDIR` or a mode-700 dir under the config dir). **But cloudflare filed it as a hardening note,
not a finding**, on the ground that impact is "bounded on a single-operator machine."

That difference is a **threat-model disagreement, not a detection miss**, and it is the most useful
single result in this comparison. Codex's manifest threat model explicitly names "a local process
running as another uid on a shared macOS host" as a secondary attacker; cloudflare's
`architecture.md` — which I wrote from blind recon — modelled one operator on one machine and treated
same-uid effects as non-crossing. Both tools saw the same bytes; they priced the second-uid attacker
differently. **Which is right is the operator's call, not the tools'**, and it is the one genuine
value fork this experiment surfaced.

No attack-class file "should have" caught F2 and failed to. `DESKTOP-MOBILE-AND-LOCAL-IPC.md#Local
file ownership and TOCTOU` was selected and did fire; the class worked and the *severity model*
diverged.

## 3. False-positive discipline

**Cloudflare, measured from its own artifacts:**

| | count |
|---|---|
| candidates raised by 9 hunters | **58** distinct fingerprints |
| proposed `confirmed` by hunters | **0** (structurally impossible — no sandbox) |
| given to an independent Phase-3 verifier | **10** |
| survived as `needs_validation` | **8** |
| **rejected** by the verifier | **2** (20% of adjudicated) |
| promoted to `confirmed` | **0** |
| unvalidated, budget-exhausted | **48** |

The two rejections are the discipline working, and both cite the skill's own gates:
`hooks/task-quality-gate.sh:phase0-verify-exit-status-always-zero` — *"Dead branch real, but model
controls the trigger; no boundary, resource, or consent effect"* (a correctness bug, not a security
finding); and `hooks/mailbox-drain.sh:peer-body-spliced-unescaped…` — *"Trace accurate but terminates
in model-context text; prompt injection alone, no code-level boundary crossed"*, which is
`AI-AND-LLM.md` Core discipline applied verbatim. Independent hunters also disagreed with each other
in-band: two reviewed the same `python3 -c` interpolation and one called it hardening (path is
harness-supplied) while the other called it a candidate (parent directory is agent-creatable); the
verifier adjudicated for the candidate, on the ground that the sweep globs agent-creatable dirs and
the UUID check binds only the basename.

**Codex: not computable from its artifacts.** Its `coverage.json` records 7 surfaces with
dispositions (2 `reported`, 4 `no_issue_found`, 1 `not_applicable`) and its `findings.json` holds 2
findings. **It records no rejected candidates at all**, so a raised-vs-confirmed ratio cannot be
derived. Both its findings carry `confidence.level: high` with an execution-grounded rationale, so
its *precision on what it shipped* looks excellent — but its recall and its discard rate are both
invisible. Cloudflare retains `rejected` records in `findings.json` by design, explicitly "so future
runs do not repeat the unsupported claim without changed evidence." **That is a real structural
advantage for cloudflare on this axis**, independent of this run's numbers.

## 4. Coverage honesty

**Does cloudflare's `coverage-ledger.json` name what it did not cover? Yes, at finer granularity
than codex — and it refuses to claim completeness at all.**

| | codex `coverage.json` | cloudflare `coverage-ledger.json` |
|---|---|---|
| unit | risk-area **surface** | **surface × boundary × subsystem × attack-class** |
| units | **7** | **40** |
| per-unit evidence | a `notes` prose string | `reviewed_paths` + per-check `{agent_id, invariant, method, result, artifact}` + `unresolved` |
| file inventory | yes — 69 files, "every file accounted for" | **no** — the ledger never enumerates the 69 files |
| completeness claim | **`"completeness": "complete"`, `deferred: []`** | **`run_status: "incomplete"`, `incomplete_reason: "validation_budget_exhausted"`** |
| names its exclusions | yes — `hooks/tests/**` with reason, + 2 `openQuestions` naming settings.json arrays and bin/+scripts/ (~39k lines) | yes — 6 companion attack-class files excluded, each with a source fact; 48 named unvalidated fingerprints; `phase5_status: "not_run"` |

**Validators — both run, both pass.**
`node validate-coverage-ledger.cjs coverage-ledger.json` → `PASS: 40 coverage units valid`.
`node validate-findings.cjs findings.json` → `PASS: 10 findings valid`.

Two things about those passes matter more than the passes:

1. **`validate-findings.cjs` caught a real error the agents made.** First assembly failed:
   `ERROR: $[3].trace[4].kind: must be "propagation", got "sink"` and the same at `$[9].trace[3]`.
   Two independent verifiers emitted multi-sink traces because the defects genuinely have several
   sinks; the schema requires a multi-entry trace to open `entrypoint`, close `sink`, and label the
   rest `propagation`. A 2-in-10 agent error rate on one field, caught mechanically. The parent
   applied the non-material relabel that VALIDATION-AND-REPORTING permits directly.
2. **`validate-coverage-ledger.cjs` is a consistency checker, not a coverage attestation.** Run
   against `[]` it returns `PASS: 0 coverage units valid`, rc 0. SKILL.md says so itself —
   "Validator success proves format and ledger consistency only." A green ledger validator is
   therefore *no evidence whatsoever* that anything was audited.

**The decisive result on this measurement is about the control arm.** Codex asserts
`"completeness": "complete"` and one of its seven surface dispositions is **factually false**:

> `surface_network_egress` — `disposition: "not_applicable"` — *"No curl, wget, nc, ssh or scp
> invocation exists anywhere in scope; hooks are local-only."*

At that exact sha, `hooks/push-critical.sh:62` is
`curl -s --max-time 4 -X POST https://api.pushover.net/1/messages.json`. I verified this directly in
the content-matched snapshot, and two cloudflare hunters cited it independently — one of them raising
`hooks/push-critical.sh:unencoded-form-field-interpolation`, an unencoded `-d` form body carrying
payload-derived text to a third-party endpoint. Codex declared an entire risk area not-applicable on
a premise that a one-line grep refutes, and its `complete` flag gave that error the appearance of
settled coverage. Two further codex `no_issue_found` surfaces are contradicted by cloudflare's
*verified* records — `surface_json_decision_integrity` (codex: "Peer hooks build decision JSON with
`jq -nc --arg`, which is safe by construction" — false for `agent-teams-enforce.sh:59` and
`check-edit-boundary.sh:137`) and `surface_path_handling` (codex checked `backup-before-write.sh`'s
destination path, which is sound; cloudflare found the defect on a different axis, the prune's glob).

So on coverage honesty the two tools fail in opposite directions, and the asymmetry is not
symmetric in cost: **cloudflare under-claims and names its gaps; codex over-claims and one
over-claim was wrong.** Cloudflare's structural protection here is a rule, not a habit — "Never
imply that one run exhausts the target."

## 5. The incremental claim — would a second run at TRUNK skip unchanged units?

**No. It would re-seed every unit and re-decide each one. Answered from SKILL.md §"Coverage and
prior runs" (6 rules) + RECONNAISSANCE.md §"Prior-run input", not from the README.**

- **R1** — *"A prior source ref alone is not evidence that a path is unchanged."* The gate is a
  per-unit **source comparison the parent must perform**; a sha is explicitly rejected as evidence.
  Rule 1 alone therefore *adds* parent work proportional to the prior ledger and removes none.
- **R2** — a prior `confirmed` with unchanged source is carried, but is linked to a current unit
  seeded `planned` and **still sent through the current verification path**. Only that one root cause
  leaves the hunter exclusion list. **One hunter's attention saved; one verifier still spent.**
- **R3** — a prior `confirmed` whose source changed is **not** excluded from hunting and "remains
  confirmed only if current independent validation establishes the current path and result" — a full
  re-hunt plus re-verify.
- **R4** — every prior `needs_validation`, `deferred`, `blocked`, `out_of_scope` and changed-source
  unit "become current work"; "these prior states never suppress a current unit."
- **R5 — decisive.** The strongest state a clean prior unit reaches is `covered`, and R5 gives
  `covered` **no suppression power**: it "may inform priority, but it remains visible in the current
  ledger." HUNTING.md confirms the disposal — "use the coverage critic to decide whether it needs
  another pass" — and the `deep` profile gives `prior_covered_same_source` units "an independent
  second pass."
- **R6** — a prior `quick` or **scoped** ledger "contributes only its recorded evidence and gaps,
  never an implied 'rest is fine.'" Our run is scoped, so it contributes even less.

**What carrying a prior ledger actually buys is exactly one narrow thing:** hunter-exclusion of an
unchanged confirmed root cause (R2). Everything else is unchanged work or added work. The protocol is
**revalidation-with-memory, not incremental scanning** — an anti-false-negative design that achieves
its property by paying full price again. Its real products are (a) stable fingerprints so one defect
keeps one identity across runs, (b) retained `rejected` records so a refuted claim is not re-reported,
and (c) a priority ordering. **None of those is a reduction in agent invocations, which is the skill's
own unit of spend** ("one unit is roughly one hunter assignment").

**For this repo specifically this is the worst case.** `hooks/` has moved a lot since July, so at
trunk nearly every unit classifies changed-source under R3 — full re-hunt — *and* the parent
additionally pays R1's per-unit diff. A `dc12c8db` ledger would buy a trunk run almost nothing beyond
fingerprint identity for any confirmed record that survived unchanged. And since this run produced
**zero** confirmed records, and R2's carry applies only to `confirmed`, **a trunk run would inherit no
exclusions at all.**

*Caveat, stated rather than hidden:* the rules bound what the parent may SKIP, not how coarsely it
may SEED. A later run could legitimately seed fewer units if the architecture simplified. That is
rescoping, not incrementality, and R6 forbids reading a narrower prior scope as reassurance.

---

## Cost

| | codex (control) | cloudflare (treatment) |
|---|---|---|
| wall clock | 17 min (05:38:18 → 05:55:00 from the manifest) | ~19 min of agent time, ~75 min including parent orchestration |
| agent invocations | not recorded in its artifacts | **24** (4 recon + 9 hunters + 1 critic + 10 verifiers) against a 30 budget |
| subagent tokens | not recorded | ~3.6M across hunters + verifiers |
| findings shipped | 2, both severity-scored, both execution-grounded | 8 `needs_validation` + 2 `rejected`; **0 confirmed, 0 severities** |

Roughly **12× the agent cost for 3.5× the distinct verified defect classes** (7 vs 2), with the
caveat that cloudflare's carry no severity and no reproduction, because the skill forbids producing
one here.

## What I could NOT measure

1. **Codex's false-positive rate.** Its artifacts record no rejected candidates, so raised-vs-shipped
   is underivable. The comparison in §3 is one-sided by construction.
2. **Confirmed-tier quality for cloudflare.** No OS sandbox ⇒ the `confirmed` branch was unreachable.
   Every cloudflare finding here is one tier below codex's two on evidentiary strength, and that gap
   is the protocol's, not the run's.
3. **Whether the 48 unvalidated candidates survive adjudication.** 20% of the adjudicated sample was
   rejected; naively extrapolated that is ~10 more rejections, but the 10 were chosen for their
   bearing on measurement 2, not sampled at random, so the rate does not transfer. They are retained
   as ledger candidates with `validation_budget_exhausted` and are **not** reported as findings.
4. **Phase 5 did not run for any record.** Standard profile wants a second fresh agent to re-verify
   each retained record; the budget could not fund it. Recorded as `phase5_status: "not_run"`.
5. **Re-run variance.** N=1 per arm, no repeat. Any per-arm quality difference could be run-to-run
   noise; only the *structural* differences (confirmed-tier unreachability, rejected-record
   retention, completeness-claim polarity) are properties of the tools rather than of these runs.
6. **The codex arm's own execution claims.** I did not re-execute its reproductions; I took its
   `confidence.rationale` at its word while verifying its *source* claims, one of which was false.
7. **Whether hooks/tests/ exclusion mattered.** Cloudflare saw those files and codex did not; I did
   not isolate how much of cloudflare's extra yield depended on them.

## Recommendation for reso — INFERENCE ONLY (reso was not scanned)

Reasoned from which of the 10 companion attack-class files a Next.js/TS/SQLite(Turso)/passkeys/
Replicache/Soketi stack **activates**, since the skill's own selection rule is to select a companion
"because reconnaissance found the trust-sensitive boundary described by its `When to use this file`
section" — so an unactivated companion is dead weight and an activated one is the part doing work.

| Companion | hooks/ @dc12c8db | reso (inferred) |
|---|---|---|
| WEB-PROTOCOL-AND-AUTH | no | **YES, heavily** |
| CLIENT-SIDE | no | **YES, heavily** |
| DATA-ISOLATION-AND-LIFECYCLE | no / marginal | **YES, heavily** |
| PROTOCOLS-RPC-AND-MESSAGING | no | **YES** |
| CLOUD-AND-DEPLOYMENT | no | **YES** |
| RESOURCE-EXHAUSTION | yes, narrow | YES, broader |
| SUPPLY-CHAIN-AND-RELEASE | yes | YES |
| AI-AND-LLM | yes, centrally | conditional |
| DESKTOP-MOBILE-AND-LOCAL-IPC | yes, centrally | no |
| MEMORY-SAFETY-AND-BINARY | no | no |

`hooks/` activates 4 of 10. reso activates ~7 of 10 **and lights the three heaviest**. The blocks that
would earn their keep: **WebAuthn and passkey verification** (challenge binding, RP ID,
user-verification flag, sign-count, credential-to-account binding), **Account linking and identity
collision**, **Cache deception / web cache poisoning through unkeyed input** (worse on App Router than
on a classic server, since route and data caching is on by default and a mis-keyed entry is a
cross-tenant read), **Missing tenant or owner enforcement** and **Stale authorization and derived copy
use** (Replicache makes this structural: a client view is a derived copy of authorized rows living in
IndexedDB and re-synced incrementally, so an authorization change not reflected in the pull's diff
leaves a stale-but-authorized-looking copy on the client), **Duplicate delivery and idempotency gaps**
(Replicache replays mutations by design, so a non-idempotent server mutator is a security bug),
**Topic/subscription scope gaps** (Soketi private/presence channel auth), and **Browser-storage
disclosure and stale authorization**.

**Inference:** cloudflare's roster is web/multi-tenant/browser-shaped, so its marginal value over a
generic reviewer should be materially higher on reso than on a bash hook subsystem, and that
direction is structural rather than a matter of run quality. The parts that were pure overhead here —
six unactivated companion files, the sandbox/promotion apparatus, the tenant-isolation vocabulary —
are the parts reso would actually consume. **Two things change the calculus there in cloudflare's
favour beyond roster fit:** reso is a web app, so `confirmed`-tier evidence is reachable via ordinary
offline component/integration tests *if* a sandbox is provided — which removes this run's single
biggest weakness; and reso has real tenants, so the "no cross-principal boundary on a single-operator
machine" judgement that demoted codex's F2 to hardening here would not apply.

This is inference from roster fit. Roster fit predicts where the tool has **vocabulary**, not whether
it finds a bug an ordinary reviewer would miss. The honest next step is to run this same two-arm,
matched-sha experiment on reso rather than generalise from one repo.

## Operational recommendation

Keep all three, on different axes, and do not run cloudflare unsandboxed again on a bash surface:

- **security-guidance** (diff reviewer, hooks on edit/Stop/commit) — different axis, already settled.
- **codex-security** — keep as the **confirmer**. It executes, it scores severity, it is ~12× cheaper,
  and its two findings here were both real and both reproduced. Its weakness is coverage over-claim:
  treat `"completeness": "complete"` as a claim to audit, not a fact, and spot-check any
  `no_issue_found` surface with a grep before relying on it.
- **cloudflare/security-audit-skill** — keep as the **hunter**, and give it a sandbox or accept that
  it can never exceed `needs_validation`. Its structural advantages are real and tool-level, not
  run-level: per-unit coverage accounting, retained rejected records, mandatory named gaps, and a
  refusal to claim exhaustion.

They are **not redundant on this surface.** Overlap was 2 of 7 distinct verified defect classes
(29%), in one direction only — codex found nothing cloudflare missed — and the two tools' coverage
ledgers fail in opposite directions. That is precisely the configuration where running both is worth
more than running either twice.
