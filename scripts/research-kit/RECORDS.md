# Hand-run research kit: records and interfaces

The kit of REPORT.md §8 item 7 (`docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md`). Record shapes follow
`evidence/design/SYNTHESIS.md:932-1094`; this file names only the fields the kit reads or writes, and every deviation
from SYNTHESIS. Profile names and caps come from REPORT.md §6, and live in code in `lib/kit.py` (`PROFILES`, `CAPS`,
`r_max`). Shared helpers: `lib/kit.py`. Signing: `scripts/lib/operator_sign.py`.

## Where things live

| Store | Path | Writer |
|---|---|---|
| Tracked records | `docs/research/<slug>/` in the deliverable repo (`kit.records_dir`) | each script below |
| Sealed, mode 0700 | `$CC_RESEARCH_HOME/<slug>/` (`kit.sealed_dir`), default `~/.claude/autonomy/research/<slug>/` | courier, round, seed, signoff |
| Program registry | `$CC_RESEARCH_REGISTRY`, default `~/.claude/autonomy/research/programs.json` | `gate.sh` only, via `kit.registry_set` |
| Operator signatures | `<sealed>/signoff.jsonl` | `cc-signoff research:<slug>/…` only |
| Research index | `docs/research/INDEX.jsonl` in claude-infrastructure | `research-index.py` only |

Registry entry (wave A1's contract, never extended): `{"slug","aliases","cwd_roots","state"}`, state one of
`registered → certifying (gate.sh freeze) → certified (gate.sh run, all rows pass) → build-certifying (gate.sh built-freeze) → build-certified (gate.sh built-run) → closed`; the two build states are method v1.2 (§11). A valid operator
`reopen` signature newer than the certificate makes `gate.sh run` set the state back to `registered`.
Added 2026-10-05 (wave E3d): between `build-certified` and `closed` sits `implementation-signed`
(`gate.sh built-signed`, only on a valid operator `implementation` signature of the newest built certificate);
`gate.sh close` refuses a `build-certified` program without it.

## Tracked records (fields the kit uses)

- `frame.json`: SYNTHESIS shape, plus `profile` (`lite|standard|full`), `deliverable_repo` (abs path),
  `reviewer_pins` `{anthropic, frontier, openai, google: model id}`, `reviewer_effort` `{vendor: effort}` (reviewers
  only, written by `intake.py contract-page`; absent in a frame signed before 2026-10-04 = no pin, CLI default), `rulings` `{definition_of_complete: {at, quote},
  exemption: {at, quote}}` (§3.1), `fac_map` `[{fac, row|null, na_reason|null}]` covering FAC-01..FAC-33, `reask_map`
  `[{frame, axis|null, excluded_quote|null}]`, `sources_required` `[source id]`, `populations` `[name]`,
  `known_rows` `[{id, kind:"frame-omission", names_rows:[], blocks_waves:[], resign_due, default:"descope|class-b",
  status:"open|closed"}]`, `plan` (path of the plan file relative to the records dir, or null; gate row 9 lints it and
  row 8 skips its headings) and `topic_owner` (who owns the topic, or null; gate row 8 fails while it is empty). Both
  are written by `intake.py set --plan PATH --topic-owner "<who>"`, which refuses a plan path that is not an existing
  file under the records dir and an empty or numberless-superlative owner; `init` writes both as null.
- `acceptance.json`: `{"rows":[{id, predicate, check_cmd, threshold:{metric, op, value}, negative_branch,
  control:{known_bad, known_good}, soundness, residual_label|null}]}`.
- `decisions.jsonl`: SYNTHESIS shape. The lead writes `tally` `{premises:[PR ids], flip_probe:"P-..",
  flip_result:"negative|positive|null"}`, never `conviction`; `kit.conviction` derives it. `packet`
  `{id, class:"B|C", due:ISO}`; `ruled_by` `agent|ladder|operator|packet-default`; `status`
  `open|ruled|carried|reopened|descoped`.
- `premises.jsonl`, `sources.jsonl`, `census/<pop>.json`, `contact_matrix.json`, `residual.jsonl`, `trace.jsonl`,
  `holes.jsonl`, `changes.jsonl`: SYNTHESIS shapes. `residual.jsonl` `why_unreachable` adds the method-created classes
  `depth-cap`, `stage-budget-exhausted`, `stub-validated` (§10 item 7), each needing `owner_wave`, `due`, `closing_probe`.
- `census/<pop>.json` additions (written only by `cc-research census repin`): a method may carry
  `superseded_by: <agent>`, `superseded_at: ISO`, `superseded_why: <text>`; it stays in `methods`, and gate row 2
  neither re-runs it nor counts it toward the 2 independent methods. `retired_members: [{id, at, why}]` holds members
  no active method lists any more; they left `members` and gate row 2 does not expect them in a re-run.
- `probes.jsonl` (written only by `lib/probe_run.py`, through `cc-research probe|self-test|doctor` or the `probe-run.sh` shim): SYNTHESIS shape; `evidence/<probe-id>/{cmd,stdout,stderr,env.json}`.
- `budget.json`: `{"stages":{"1":{"started":ISO,"ended":ISO|null}, …}, "overrun_packets":{"<stage>":"<packet id>"}}`.
- `rounds/<k>/matrix.json` (written by `round.sh`): `{round, kind:"frame-critique|certification|delta",
  snapshot_sha, verification_only, slots:[{pid, vendor, strategy, status:"complete|partial|dead|void", reruns}],
  lanes:{vendor:"live|dead"}, counted, new_material, seeds_caught, quiet, forecast:{p50,p90}|null, r_max}`.
  `rounds/<k>/panels/<pid>.json` (written by `courier.sh`): SYNTHESIS panel shape, raw output beside it as `<pid>.raw`.
- `cert/CERT-v<n>.json` and `.md` (written by `gate.sh run`): SYNTHESIS cert shape.

## Script interfaces

Every script: `--program <slug>` (and optionally env `CC_RESEARCH_RECORDS` for the records dir). Exit 0 ok, 1 a check
failed, 2 usage or refusal, 3 a dead vendor lane, 4 a voided slot. Python is 3.9-safe; bash is 3.2-safe.

- `courier.sh preflight` → `<sealed>/preflight.json` `{vendor:{binary, ok, model_id, error}}`; exit 3 if any lane dead.
- `courier.sh bundle --round K` → builds `<sealed>/rounds/K/bundle/`, prints `<path> <sha256 of manifest>`.
- `courier.sh run --round K --pid P --vendor V --strategy S --role reviewer|rater|verifier --brief F` → panel json
  + raw; exit 3 on a missing or failing CLI (dead slot), 4 on an integrity hit or model-id mismatch (void slot).
- `courier.sh integrity --round K` → greps every raw output for the real records path, the deliverable repo path and
  the vault path (`<sealed>/vault`); a hit voids that slot.
- Vendor binaries resolve by absolute path through the interactive shell (Anthropic: the newest versioned binary the
  `claude` launcher names); tests override with `CC_RESEARCH_BIN_ANTHROPIC|OPENAI|GOOGLE`.
- `round.sh --kind frame-critique|certification|delta --round K` → refuses past `kit.r_max` (+1 only with a VALID
  `extra-round` signature), refuses a third frame-critique round; writes `rounds/K/plan.json` then
  `rounds/K/matrix.json`. Tests override the courier with `CC_RESEARCH_COURIER`. R_max bounds COUNTED certification
  rounds; at most `UNCOUNTED_ROUNDS_MAX` rounds may be lost to a dead lane; a certification round needs a fresh
  all-live `<sealed>/preflight.json` (`cli_cert.lane_refusal`, `PREFLIGHT_MAX_AGE_S`, exit 3). Re-running a round
  that has a bundle and plan but no matrix resumes it (only slots without a complete panel run). `close` refuses a
  counted round any of whose slots is not `complete`; a lane is live only when every one of its slots completed.
- `cc-research check-round` JSON `rerun` lists every planned slot that is void, dead, partial or missing (each with
  `reason`, `reruns_left`); `voided` is the void-only subset. `open-round` refuses (exit 3) on the same preflight rule.
- Program lease `<sealed>/lease.json` `{owner, pid, host, acquired, heartbeat}` (`kit.lease_*`, `cc-research lease
  acquire|release|show`, `LEASE_TTL_S`): while a fresh lease is held, other owners' writing verbs exit 2; no lease
  file means no check. Ids are reserved under `kit.mint_id` (`$CC_RESEARCH_HOME/.mint/`); the seed vault is written
  under a lock.
- `estimate.py forecast` → JSON `{p50, p90, r_max, desk_mean, desk_n95, invisible_mean, p_any, quiet_streak,
  stop:"running|dry|cap"}` from `rounds/*/matrix.json`.
- `seed.py plant|apply|prescreen|match|status` → vault `<sealed>/vault/seeds.enc`, key from the keychain item
  `cc-research-seed-vault/<slug>` (tests: `CC_RESEARCH_VAULT_KEY`). `match` (run by `round.sh close` before quiet is
  computed) appends `{id, seed_match: <seed id>}` to `holes.jsonl` for each MATERIAL hole restating a seed's defect
  (span overlap + class + claim, not overlap alone); `prescreen --caught …` marks seeds a blind pre-screen caught
  `discarded`, so they are never planted; `status` prints a second line with seed realism beside real detection.
- `estimate.py forecast` also prints `found_raw`, `found` (deflated by `false_material_share`), `found_shadow`;
  `estimate.py calibration [--file]` prints coverage, bound sharpness and Spearman rank skill.
- Method v1.2: `estimate.py simulate|forecast` read the measured inputs from
  `docs/research/research-calibration/evidence/params-measured.json` by default (`CC_RESEARCH_PARAMS` or `--params`
  for another file; an unreadable or incomplete file exits 2). `--base` runs the pre-calibration assumed set as a
  contrast. `simulate` prints `regime: "measured|base|stress"` and its `inputs`; `forecast` prints
  `inputs: "measured|base"` with matching `assumed` and `measured` lists. `intake.py init` stamps
  `frame.json` `method_version: "1.2"` (no stamp reads as 1.1) and warns on stderr when a profile wider than lite
  leaves no fewer holes at the measured inputs.
- `cc-research probe --id P-.. --kind K --closes PR-.. -- <cmd…>`, `cc-research doctor` and `cc-research self-test`
  (each acceptance row over `control.known_bad`/`known_good`, fixture in env `FIXTURE`, as gate row 6 runs it);
  `probe-run.sh run|doctor` is a bash 3.2 shim onto the first two.
- `gate.sh register|freeze|run|render|sweep|file-packet|requires|close` (see `lib/gate.py`).
- `gate.sh requires --program P [--wave W] [--json]` (`lib/gate_requires.py`) → exit 0 the build wave may fire, 1
  refused with each reason, 2 the program cannot be read. Reads the newest certificate and the LIVE decision and
  known-row records (the sweep and the frame-delta cycle clear blocks after the certificate). The reader behind
  `handoff-fire.sh --requires-gate P --gate-wave W`.

## Method v1.2 records (REPORT.md §11 and §12; wave E3b)

Both mechanisms apply only when `frame.json` carries `method_version` `"1.2"` or later (`kit.is_v12`); absent reads
1.1. Constants: `kit.CAPS` (v1.2 block), `kit.YIELD_STAGES`, `kit.AS_BUILT_KINDS`, `kit.AS_BUILT_ENV`,
`kit.SOAK_BOUNDARIES`, `kit.BUILD_FINDABLE_SHARE`, profile keys `quiet_probes_to_stop`, `built_hard_cap`,
`built_stage_days`. Registry states gain `build-certifying` and `build-certified` (`kit.BUILD_STATES`); the entry
shape is unchanged. Wave E3d adds `implementation-signed` (`kit.IMPL_SIGNED`; `kit.STAGE9_STATES` is the three).

The implementation signature (§11 "Signing the implementation") is one line of `<sealed>/signoff.jsonl` like every
other signature: `{row: "research:<slug>/implementation", action: "implementation", target: null, at, at_iso,
evidence, pins: {"built/BUILT-CERT-v<n>.json": <git blob sha>}, provenance: {claude_ancestor, chain}}`.
`operator_sign.implementation_state(slug)` is the one reader: `signed` (a VALID record pins the newest built
certificate), `unsigned`, `void` (agent-written or no chain), `stale` (the pinned certificate changed), `superseded`
(it pins an older built certificate). Only `signed` passes `gate.sh built-signed`, `close`, `requires` and `render`.

### Stage 9 records (`docs/research/<slug>/built/`, §11)

- `built/freeze.json` (written by `gate.sh built-freeze`): `{snapshot_sha, artifact_root (abs), frozen_at,
  research_cert: "CERT-v<n>", waves_done: [wave]}`. `frame.json` `build_waves` `[wave]` is the list row 20 compares.
- `built/findings.jsonl` (written only by `cc-research built finding add|fix`): `{id: "BF-<n>", source:
  "round|mutation|contact|soak", claim, severity: "material|refinement|cosmetic", status:
  "open|fixed|rejected-no-repro", repro: {test_cmd, red: {sha, exit, at}, green: {sha, exit, at}|null}|null,
  mutant: "M-<n>"|null}`. `add` runs `test_cmd` itself in `artifact_root` and stores `red` only when it exits
  nonzero; a material finding whose command passes, or with no command, is stored `rejected-no-repro`. `fix` re-runs
  it and stores `green` only on exit 0.
- `<sealed>/built/mutants.json` (sealed, planted by hand or by a seeding script): `[{id: "M-<n>", file, search,
  replace}]`, one literal replacement each. `built/mutation.json` (written only by `cc-research built mutate`):
  `{snapshot_sha, at, baseline_exit, rows: [acceptance row id], mutants: [{id, status:
  "killed|survived|equivalent|invalid", killed_by: [row id], equivalent: {reason, rater}|null, rerun: n}], killed,
  survived, kill_rate}`. The harness is every `acceptance.json` row's `check_cmd`, run with env `ARTIFACT=<copy>`
  and cwd the copy; `invalid` is a mutant whose `search` text is absent.
- `built/contact.jsonl` (written only by `cc-research built contact`): `{id: "BC-<n>", target: "P-.."|"<acceptance
  row id>", snapshot_sha, cmd, env: {home, home_clean: true, path, interpreter, interpreter_version}, exit,
  negative_control: {ran, exit, reported_refutation, reason_if_not_run}, at}`. The runner execs `env -i HOME=<fresh
  empty dir> PATH=/usr/bin:/bin ARTIFACT=<artifact_root> /bin/bash -c <cmd>` and records what it set.
- `built/soak.jsonl` (written only by `cc-research built soak sample`): `{at, check: <acceptance row id>, exit,
  snapshot_sha}`; `built/soak.json` `{started, restarts: [{at, finding}]}`. Boundaries: `frame.json`
  `soak_boundaries` (default `kit.SOAK_BOUNDARIES`); a boundary is crossed when passing samples exist on both sides
  of it. An uncrossed boundary needs a `residual.jsonl` row `{why_unreachable: "elapsed-time", boundary, owner, due}`.
- `rounds/b<n>/matrix.json`: a `round.sh --kind built` round, the certification shape with `kind: "built"` and
  `snapshot_sha` the built snapshot. Capped by the profile's `built_hard_cap`.
- `built/BUILT-CERT-v<n>.json` and `.md` (written by `gate.sh built-run` through `built_cert.py`): `{cert, program,
  version, snapshot_sha, issued, research_cert, rows: {"20".."25": status}, findings: {material, fixed,
  rejected_no_repro}, kill_rate, forecast: {before_observed, before_forecast, after_mean, after_bound95, share,
  assumed: [..]}}`. `CERT-v<n>.json` `forecast` gains `before_impl_mean`, `after_impl_mean`, `after_impl_bound95`,
  `build_findable_share`.

### Yield and blocker records (§12)

- `yield.jsonl` (written only by `cc-research yield find`): `{probe: "P-..", ref: <id>, ref_kind:
  "premise|hole|change|residual|frame-row", stage, at}`; refused unless the ref exists (a premise ref must read
  `verdict: "refuted"`).
- `budget.json` `stages.<3|5>.stop` (written by `cc-research budget end` under a 1.2 frame): `{reason:
  "quiet|ceiling", ceiling: "days|probes"|null, k, streak, counted, finds, yield_per_day, escape_cost_days, voi, at}`.
- `cc-research yield show --program P --stage N [--json]` → `{stage, verdict: "continue|stop|ceiling", …the stop
  fields}` (`yield_stop.evaluate(ctx, stage, as_of=None)`, the one implementation rows and verbs share).
- `decisions.jsonl` gains `timebox_days` and `research_started` (ISO), set at `decision add`. `blockers.tag(ctx,
  decision)` → `{tag: "research|production|operator"|null (null at 90+), conviction, gaps: [premise id],
  reachable_max, at_ceiling: bool, extended: bool}`. Extension signature: `cc-signoff
  research:<slug>/extend-decision/<decision id>` (`operator_sign.ACTIONS`).
- `cc-research menu --json` items for a research-tagged decision: `{id: "extend-decision/<D>", label, price, effect}`.

## `bin/cc-research` (wave 2, REPORT.md §8 items 9–12 and 15)

`bin/cc-research <verb>` → `lib/cli.py`, which lists the module owning each verb. It reads and writes the records
above and nothing else; the kit scripts stay as thin compatibility entry points over the same modules. Verbs that
read one program take `--program P` (`verdict` also takes the slug positionally: `cc-research verdict <slug>` is the
certificate read the research block whitelists, `router.py` `cert_read`). Names the block treats as buying verbs
(`router.py` `CC_RESEARCH_BUYING`): `reopen`, `extra-round`, `round`, `frame-critique`, `rehearse`.

Cross-module contracts (a consumer depends on exactly these shapes):

- `cc-research verdict [--program] P [--json]` → the `gate.sh render` state lines, then an operator block (pending
  concerns, "waiting on you since <date>", the priced menu). `--json`: `{program, state, lines:[…],
  pending_concerns:N, waiting_since:ISO|null|"unknown" (null: nothing open; "unknown": cc-decide unreadable), menu:[{id, label, price, effect}],
  overridden_relays:N}`.
- `cc-research pending --json` → `{programs:[{program, state, pending_concerns, waiting_since, menu:[…],
  overridden_relays:N}]}` over every registry program not `closed` (`overridden_relays` is `null` on a program that
  could not be read). Read by `hooks/operator-readout.sh` and `scripts/wrap-ledger.sh`.
- `$CC_RESEARCH_HOME/route-counters.json` = `{"programs": {"<slug>": {"overrides": N, "last_override_at": "<ISO>"}}}`:
  how many relays the operator overrode as `misrouted`. Written by `router.py` `prompt` on an accepted `misrouted`;
  read by `lib/cli_core.py` `overridden_relays`, which reads 0 when the file is missing or garbled. It holds one small
  object per program, so it does not grow.
- `cc-research census repin --program P --pop POP --method NEW --supersedes OLD --count N --cmd CMD --why TEXT
  [--items-file F]` re-baselines a census whose population changed after its methods were pinned: it runs CMD as
  `census add` does, marks OLD superseded, appends NEW, re-runs every active method, and sets `members` to their
  union (the rest move to `retired_members`). It refuses, writing nothing, on an unknown or already-superseded OLD, a
  NEW that is already a method, an empty `--why`, or active methods that disagree.
- `cc-research concern add --program P --text T [--raised-by operator|agent|sweep|build|rehearsal]` appends a
  `challenges.jsonl` row with `triage: "pending"`; `cc-research concern list --program P [--pending] [--json]`.
- `cc-research triage --program P` buckets pending challenges by the §5.2 table through a blind rater, appending
  triage events to `challenges.jsonl` (and `changes.jsonl` for counted buckets), and is the writer of
  `$CC_RESEARCH_HOME/activities.json` (`lib/activities.py`; shape in `router.py`'s header).
- `cc-research job sweep|freshness|triage|drift|market [--program P]` → one scheduled pass (no `--program`: every
  registry program in `certifying|certified`). The launchd runners in `scripts/research-kit/jobs/` call only this.
- `cc-research reference-class record|show|check` → `docs/research/research-reference-class.jsonl` in
  claude-infrastructure (append-only).
