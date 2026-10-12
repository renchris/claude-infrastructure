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
  status:"open|closed"}]` (later events, and rows held without re-signing the frame, are lines of `known_rows.jsonl`
  folded over these by id; a row may carry `hole`, see "Held frame omissions and re-finds" below), `plan` (path of the plan file relative to the records dir, or null; gate row 9 lints it and
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
- `premises.jsonl` later events (the fold reads the last value of each field):
  - `cc-research job freshness` appends `{id, probes:[..., "P-fresh-<id>[-rN]"], rechecked_by, recheck_verdict:
    "holds|refuted"}`, plus `carried: true` on a premise's first re-check. It never writes `verdict`. While the
    program is certifying, a carried premise with no verdict probe in the last 20 h (24 h less a 4 h margin) is
    re-run under the next `-rN` id; its probe joins `probes`, so a fresh live read renews its level (gate row 4).
  - `cc-research premise revise --id PR-n --why "<reason>"` with any of `--recheck-cmd <cmd>` (and optionally
    `--repointed-from <probe id>`), `--retire-recheck`, `--verdict holds|refuted|partial|unknown` (`refuted` needs
    `--refuted-by <probe or challenge id>`, which must exist), or `--load-bearing-for <id>` repeated (replaces the
    list; `''` alone clears it) appends `{id, recheck_cmd?, recheck_repointed_from?, verdict?, refuted_by?,
    load_bearing_for?, revised: true, why}`. A prose `--recheck-cmd` is refused, as the freshness job refuses to run one.
  - Gate row 4 asks that a refuted premise's `DR` dependents be revised (ruled, reopened, carried or descoped) at or
    after the ts of the event that set `verdict` to `refuted`, not the folded ts, so a later re-check or revision
    event does not re-open them.
- `census/<pop>.json` additions (written only by `cc-research census repin`): a method may carry
  `superseded_by: <agent>`, `superseded_at: ISO`, `superseded_why: <text>`; it stays in `methods`, and gate row 2
  neither re-runs it nor counts it toward the 2 independent methods. `retired_members: [{id, at, why}]` holds members
  no active method lists any more; they left `members` and gate row 2 does not expect them in a re-run.
- `probes.jsonl` (written only by `lib/probe_run.py`, through `cc-research probe|self-test|doctor` or the `probe-run.sh` shim): SYNTHESIS shape; `evidence/<probe-id>/{cmd,stdout,stderr,env.json}`.
- `budget.json`: `{"stages":{"1":{"started":ISO,"ended":ISO|null}, …}, "overrun_packets":{"<stage>":"<packet id>"}}`.
- `rounds/<k>/matrix.json` (written by `round.sh`): `{round, kind:"frame-critique|certification|delta",
  snapshot_sha, verification_only, slots:[{pid, vendor, strategy, status:"complete|partial|dead|void", reruns}],
  lanes:{vendor:"live|dead"}, counted, new_material, seeds_caught, quiet, forecast:{p50,p90}|null, r_max,
  artifacts:[hole id], splits:[{from, to}], refinds:[{hole, of}], reproductions:[{hole, status}],
  kappa:{materiality:κ|null, n, below:0.7, repass:bool, unstable:bool},
  reclosed?:[{at, reason, previous:{new_material, seeds_caught, quiet, forecast, r_max, kappa}}]}`. `reclosed` is
  appended by `round.sh close --round K --reclose --reason …`, which re-runs seed match on a closed round (the
  newest of its kind; refused once a later one opened) and recomputes what close computed. `new_material` leaves
  out seed-tagged holes, `kit.settled_out` holes (an artifact, or a split-off hole not yet verified on the real
  plan) and `kit.held_refind` holes (listed in `refinds`); `seeds_caught` counts seed-tagged holes only, so it agrees with the vault. `kappa` and the settling
  records are under "Settling a round" below.
  `rounds/<k>/panels/<pid>.json` (written by `courier.sh`): SYNTHESIS panel shape, raw output beside it as `<pid>.raw`.
- `cert/CERT-v<n>.json` and `.md` (written by `gate.sh run`): SYNTHESIS cert shape.

## Script interfaces

Every script: `--program <slug>` (and optionally env `CC_RESEARCH_RECORDS` for the records dir). Exit 0 ok, 1 a check
failed, 2 usage or refusal, 3 a dead vendor lane, 4 a voided slot. Python is 3.9-safe; bash is 3.2-safe.

- `courier.sh preflight` → `<sealed>/preflight.json` `{vendor:{binary, ok, model_id, error}}`; exit 3 if any lane dead.
- `courier.sh bundle --round K` → builds `<sealed>/rounds/K/bundle/`, prints `<path> <sha256 of manifest>`.
  The bundle is the seeded plan plus the records, less `courier.EXCLUDE` (the hole ledger, rounds, cert, changes,
  verdicts, `freeze.json` and `freezes.jsonl`, whose `plan_lines` is the seeded copy's size) and less round history
  (`withhold_round_history`, added 2026-10-12): a file a settling record cites as evidence, a file under `evidence/`
  named `w<wave>-r<round>-…`, any file whose name or prose cites a hole id (`H-<round>-<n>`), and each JSONL line
  or JSON array element that cites one (a `trace.jsonl`, `known_rows.jsonl` or `apply-at-build.jsonl` row, a
  `frame.json` known row). The plan copy is never filtered. What was withheld is named on stderr.
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
  (span overlap + class + claim, not overlap alone, or a quote of text only the seed's replacement holds; a
  class disagreement vetoes either). Spans are those of the SEEDED copy the reviewers read, recomputed by the
  apply loop and widened by `SEEDED_SPAN_SLACK`, beside the author's `detect_span`; a locus `lines` may list
  `;`/`,`-separated ranges. `--plan` is the real plan: one missing most live anchors is refused; `prescreen --caught …` marks seeds a blind pre-screen caught
  `discarded`, so they are never planted; `status` prints a second line with seed realism beside real detection.
  A seed's `detect_span` (real-plan numbering) stands in only for a seed round K's copy does not hold; `match
  --round K` tests only round K's own holes (2026-10-12: an earlier round's hole cites that round's copy, so its
  tag, or its lack of one, is frozen at that round's settle and a seed applied later can never be credited to it);
  a hole is tagged only with a seed applied in round K's copy; an `artifact` or `split_from` hole is never tagged and never
  catches. `match --dry-run` loads the vault, writes nothing, and prints `would tag: <hole ids>`, `would catch: N ·
  would orphan: N`, and the round's already-tagged holes the matcher no longer derives (match never removes a tag).
- `seed.py explain --program P --round K --plan CURRENT --hole ID…` (read-only; the kit owner runs it, not the
  lead) prints the recomputed round-K copy's sha256 and line count, then per hole: tagged, whether the closest seed
  is its tag, and that seed's rule outcomes — path, class `agree|veto|none`, quote evidence `hit|none`, span
  `exact|slack|detect_span|none`, "span only via detect_span", the claim's token ratio against 0.50, matches, and
  the first failing rule. It never prints a seed's sid, state, op type or text (an omission and a replace seed print
  alike). Each call appends `{at, by, round, holes, copy_sha256}` to `<sealed>/explain.jsonl`.
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
- `gate.sh file-packet --program P --decision D --class B|C … [--revisit-trigger T]` (`lib/gate_sweep.py`) → exit 2,
  filing nothing, when a class-B packet sits on a `reversible` decision with no `revisit_trigger` (on the record or
  passed as `--revisit-trigger`), or when its `--option` labels are not exactly the decision's `options` labels (none
  invented, none dropped). `--revisit-trigger` is written onto the decision with the `packet` field. When `sweep`
  applies a fired class-B default, the `ruled_by: packet-default` line carries the decision's `revisit_trigger`, as
  `cc-research decision rule` does, so gate row 5 passes the ruled reversible row.
- `gate.sh requires --program P [--wave W] [--json]` (`lib/gate_requires.py`) → exit 0 the build wave may fire, 1
  refused with each reason, 2 the program cannot be read. Reads the newest certificate and the LIVE decision and
  known-row records (the sweep and the frame-delta cycle clear blocks after the certificate). The reader behind
  `handoff-fire.sh --requires-gate P --gate-wave W`.

## Settling a round (`lib/settle.py`, verbs on `round.sh`; added 2026-10-11)

Before any plan edit, a closed certification round's holes can be settled honestly, seed-blind for the lead. Every
verb runs under the program lease, appends events to `holes.jsonl` (the fold keeps the newest), and refuses with
exit 2. `--evidence` files must sit inside the records dir (gate row 8 fails a record citing `/tmp`). `by` is
`kit.lease_owner()`.

- **Artifact** — `round.sh artifact --program P --hole H --reason T --evidence F…` appends `{id, event:
  "artifact", artifact:{at, by, reason, evidence:[path], plan_blob}}`. Only for an UNTAGGED, CONFIRMED, MATERIAL
  hole the lead proved is damage the seeded copy did (an omission's visible gap), and at least one evidence file
  must name the real plan's git blob (`git hash-object`), so the checks are shown to have run on the real plan. No
  `seed_match`, no catch credit: seed match skips it, round close and `estimate.counted_holes` leave it out, and
  close lists it in `m["artifacts"]`.
- **Split** — `round.sh split --program P --hole H --findings FID… --path F --lines L --quote Q --claim C --reason
  T --evidence F…`. Only for a seed-tagged, CONFIRMED, MATERIAL hole whose merged findings also hold a defect of
  the REAL plan. The original keeps its `seed_match` (the catch stands) and gets `{id, event: "split", split_to:
  [new id], split:{at, by, reason, evidence, plan_blob, to}}`. The new hole, `{id, event: "raise", round, source,
  split_from: H, findings:[FID], claim, locus:{path, lines, quote, numbering: "real"}, plan_blob, split:{…}}`, is
  opened from the named raise events (each FID must be a `finding` of one of H's raise events, none already split
  off, and at least one must stay with H); its quote must sit on its cited lines of the real plan. The id is minted
  under the mint lock with the original's padding (`H-1-022` → `H-1-072`). Seed match skips it.
- **Verify-split** — `round.sh verify-split --program P --hole NEW --status CONFIRMED|REFUTED|CONTACT --read-plan F
  --by WHO --evidence F…` appends `{id, event: "verify", verification:{status, against: "real", plan_blob, by,
  evidence, at}}`, refused unless F (the plan the verifier read) has the blob the split recorded and the real plan
  is unchanged since: never the seeded bundle. Until then the hole is `kit.settled_out`, and `round.sh close` (and
  `--reclose`) refuses its round. Rating it goes through the usual three-rater path. A second `verify-split` is
  refused.
- **Reproduce** (added 2026-10-12; REPORT.md §6.5, "Disputed finding — 1 reproduction probe") — `round.sh reproduce
  --program P --hole NEW --status CONFIRMED|REFUTED --read-plan F --by WHO --reason T --evidence F…`. The one second
  verdict a split hole can get, and only when its `verify-split` verdict was CONTACT. Refused unless F and the real
  plan both still have the blob the split recorded (so before any plan edit), unless an evidence file names that
  blob, and a second time for the same hole. Appends `{id, event: "reproduce", verification:{status, against:
  "real", plan_blob, by, evidence, at}, reproduction:{at, by, reason, evidence, plan_blob, status, first:{the
  CONTACT verification}}}`. Round close and `estimate.counted_holes` read `verification.status`, so a CONFIRMED
  one counts once rated and re-closed, and a REFUTED one joins the forecast's false share; close lists both in
  `m["reproductions"]`.

### Held frame omissions and re-finds (added 2026-10-12; REPORT.md §5.4)

A clause-(g) frame-omission hole the operator sends to the post-certificate frame-delta cycle is HELD: an open
`frame-omission` known row names it in `hole`. The row lives in `known_rows.jsonl`, not `frame.json`, so the frame
signature stays valid. `kit.held_frame_omissions` is the one reader.

- **Hold** — `round.sh hold-g --program P --hole H --known-row KR-<n> --names-rows ROW… [--blocks-waves W…]
  --resign-due YYYY-MM-DDTHH:MM:SSZ [--default class-b|descope] --reason T --evidence F…` appends `{id: KR-<n>,
  kind: "frame-omission", hole: H, names_rows, blocks_waves, resign_due, default, status: "open", held:{at, by,
  reason, evidence}}` to `known_rows.jsonl`. Only for a CONFIRMED MATERIAL hole not rated under another clause;
  refused for a known-row id that exists, a hole already held, and a `resign_due` that is not in the future (the
  hourly sweep closes an overdue row by its default, which un-holds the hole). The held hole still counts in its
  own round.
- **Re-find** — `round.sh refind --program P --hole NEW --of H --reason T --evidence F…` appends `{id: NEW, event:
  "refind", refind_of: H, refind:{at, by, reason, evidence}}`. The lead runs it after dedup (the adjudicator stays
  blind to round history). Refused unless H is held, NEW is from a later certification round, and NEW is neither
  seed-tagged nor settled. A re-find of any other hole, a fixed one included, gets no record and is new material.
- While H's known row is open, round close and `estimate.counted_holes` leave NEW out of new material
  (`kit.held_refind`), and close lists it in `m["refinds"]`. Once the row closes, a re-close counts NEW again.
- **Rating re-pass** (REPORT.md §6.5, "Rating re-pass when agreement is low — Once — 'Adjudication unstable'
  printed"). Close writes `m["kappa"]`: Cohen's kappa of rater 1 against rater 2 on MATERIAL-or-not over the
  round's holes both rated (`kit.materiality_kappa`; `materiality.raters` keyed `"1"` or `"r1"`, a code or
  `{rating}`), and prints "rating re-pass due" below `kit.KAPPA_REPASS_BELOW` (0.7). `round.sh repass --program P
  --round K --ratings F --reason T` takes F as JSONL `{id, raters:{"1","2","3"?}, level, clause?}` covering every
  hole of the kappa sample, refuses a level that disagrees with 2-of-3 M, appends per hole `{id, event: "repass",
  round, materiality:{level, clause, raters, repass:{at, by, reason, kappa_before}}}` (it supersedes the earlier
  ratings in the fold), then re-closes the round. Refused when kappa is not low, when the round is not closed or a
  later one opened, and a second time for the same round. A kappa still below 0.7 after it sets
  `kappa.unstable`; `gate.sh run` copies those rounds to the certificate's `adjudication_unstable`, and the
  render's first line starts "Adjudication unstable (round K: …) · ".

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
  NEW that is already a method, an empty `--why`, or active methods that disagree. When every method of a population
  is stale, repeat `--method`/`--supersedes`/`--count`/`--cmd` (and `--items-file`, if used) once per method, paired
  by position, so all of them are re-pinned in one all-or-nothing call: re-pinning them one at a time is refused,
  because the agreement check re-runs the stale method left behind (added 2026-10-12, census P7 of truememory-2-0).
- `cc-research concern add --program P --text T [--raised-by operator|agent|sweep|build|rehearsal]` appends a
  `challenges.jsonl` row with `triage: "pending"`; `cc-research concern list --program P [--pending] [--json]`.
- `cc-research triage --program P` buckets pending challenges by the §5.2 table through a blind rater, appending
  triage events to `challenges.jsonl` (and `changes.jsonl` for counted buckets), and is the writer of
  `$CC_RESEARCH_HOME/activities.json` (`lib/activities.py`; shape in `router.py`'s header).
- `cc-research job sweep|freshness|triage|drift|market [--program P]` → one scheduled pass (no `--program`: every
  registry program in `certifying|certified`). The launchd runners in `scripts/research-kit/jobs/` call only this.
- `cc-research reference-class record|show|check` → `docs/research/research-reference-class.jsonl` in
  claude-infrastructure (append-only).

## A running program: the front-end return, the profile switch, the re-rendered contract page (added 2026-10-12)

Three additions for a certifying program that takes REPORT.md §6.1's front-end return and then narrows its profile.
None edits `frame.json` beyond the contract page's own two fields.

### `gate.sh return-activity --program P --area A --because "<the recorded course and areas decisions>"`

Prints the id of area A's open `front-end-return` activity, opening one if none is open (`lib/activities.py`
`open_return`). The row in `$CC_RESEARCH_HOME/activities.json` carries `area`, `n_hat`, `design_holes`,
`after_round`, `opened_at` and `because`.

- **Window.** The registry reads `certifying`, `freeze.json` exists, the newest certification round is closed, at
  least one is counted, and `rounds/<next>` does not exist. A second call for an open area prints the same id, and
  only inside that window.
- **Trigger.** `estimate.py forecast` `n_hat` is above `FER_FACTOR` (1.5, assumed: §6.1 says "well above", audit
  row 16 proposes 1.5×) times the design point of the frame's profile.
- **Once per area, capped.** An area whose return has closed is refused (§6.5). A new area is refused past the
  current round profile's cap, `FER_AREAS`: lite 1, standard and full 3 (§6.1's ceiling formula). Open every area
  before signing a switch to lite.
- **Effect on the round.** Opening closes the open `certification-round` activity, and `round.py` `plan_slots`
  refuses a certification round while any return is open, so `cert-activity` refuses too. `gate.sh freeze` closes
  every return, then opens the round's activity again under a new id.
- **What the tag unlocks, while `certifying` only** (`router.py`): `[activity:<id>]` anywhere in an Agent, Task or
  Workflow input, and `CC_RESEARCH_ACTIVITY=<id> codex exec` in a read-only sandbox. Nothing else: no `round.sh`, no
  `courier.sh`, no other vendor CLI, no `claude -p`, no `cc-research` buying verb, and nothing once `certified`.
  `handoff-fire.sh` stays denied under every activity tag except `self-close` (operator ruling 2026-10-11), so the
  lead fires each area's workers from its own turn and a worker at its context limit notifies back and self-closes.
- **Not enforced:** the tag does not tie a call's work to its area; that is the brief's job.

### The profile switch: `cc-signoff research:<slug>/profile/<name> --because "<why>"` (operator, own terminal)

One line in `<sealed>/signoff.jsonl` with `action: "profile"`, `target` the new profile, plus `from` (the frame's
profile) and `after_round` (K, the certification rounds counted when it was signed). `kit.profile_switch` reads the
newest VALID one; an agent-written record or one with no chain is void and switches nothing. There is no agent verb:
without the signature the program stays on its frame's profile.

- **Refused at signing** unless the program is `certifying`, the newest certification round is closed and the next
  has not started, the target has a lower hard cap than the frame's profile, no valid switch exists yet (one per
  program), and K is at least 1 and below the target's hard cap (a round is still left to run as the
  verification-only cap round).
- **The rule for R_max** (`kit.round_cap`): `min(target hard cap, K + kit.r_max(target, round-1 p90))`, `+1` only
  for a VALID `extra-round` signature. `kit.r_max(target, p90)` is §3.8's own cap on the target profile, `min(p90 +
  4, hard cap)`, and the p90 is still round 1's recorded forecast. For standard to lite after round 1 this is
  `min(6, 1 + 6) = 6`: rounds 2–6 run on lite. The outer `min` is what keeps a switch from buying rounds: the total
  never exceeds the narrower profile's hard cap, whatever K is.
- **What follows the switch** (`kit.round_profile`): reviewers per round and quiet rounds to stop for the
  certification and delta rounds still to run (`round.py` `plan_slots`), the stop state and `r_max` in `estimate.py
  forecast`, gate row 16, the `cc-research` extra-round menu, the return's area cap, and the certificate, whose
  `profile` is the new one and whose `profile_switch` prints as "lite profile from round K+1, standard through
  round K".
- **What stays on `frame.json` `profile`:** everything signed in days or seeds. The six stage budgets
  (`cc-research budget`, the yield stop), the §6.1 ceiling and its v1.2 additions (`cc-research ceiling`, so
  standard's 28 days stay 28 and the calendar ceiling date does not move), the design point, the original seed count
  (`seed.py`), and Stage 9's built-round cap and budget.

### `intake.py contract-page` once a certification round is counted

Before any counted certification round the page is unchanged: the forecast at the profile's design point, and the
five frame fields it has always written. Once `estimate.counted_rounds` is non-empty it is a re-render:

- The profile section names the round profile (with a signed switch: "lite from round K+1 (standard through round K;
  switched by your signature of <time>)"), its reviewers per round, quiet rounds to stop and the round cap from
  `estimate.py forecast`, with the original seeds, stage budgets and ceiling still the frame profile's.
- The forecast line is this program's own `estimate.py forecast`: material holes found, `n_hat` and its 95% bound
  (`found + desk_n95`), the false-material share and its source, desk-detectable and invisible changes after signoff
  with their 95% bounds, and `p_any`. No design-point simulation is run or printed.
- It writes `CONTRACT.md` and only `contract_page_at` and `contract_page_sha256` in `frame.json`
  (`intake.RERENDER_KEYS`). It never adds `reviewer_effort`, `reviewer_pins` entries or `reference_override`, and
  prints the reviewer effort the signed frame carries (or "none pinned"). It refuses if the frame carries no
  contract page to re-render. The two changed fields make the frame signature stale by design: the operator reads
  the new page and signs `cc-signoff research:<slug>/frame` again.

### An operator-ruled reopen of a ruled decision: `cc-research decision reopen`, then `decision rule --by operator`

For a ruled decision whose flip condition fired and which the operator re-plans (§6.5: a decision is reopened at most
`kit.CAPS["refutation_reopens"]` = 2 times). `decision rule` alone cannot take it: it needs status `open` or
`reopened`, and rules as agent only at a derived 90.

- `cc-research decision reopen --program P --id D --because "<what fired>" --receipt "<the operator's words>"`
  appends `{status: "reopened", reopened_by: "operator", reopened_because, reopen_receipt, reopened_at, reopens: n}`.
  Refused unless the decision is `ruled`, and once its `reopened` events number 2. While `reopened`, gate row 5
  fails on it and `gate.sh requires` blocks its waves.
- `cc-research decision rule --program P --id D --chosen <option> --by operator --receipt "<his words>"
  --revisit-trigger "<trigger>"` appends `{status: "ruled", ruled_by: "operator", chosen, receipt,
  revisit_trigger}`. No 90 rule applies; both `--receipt` and `--revisit-trigger` are required. Refused unless the
  decision is `reopened` with `reopened_by: "operator"`: an open decision still goes to him as a packet
  (`gate.sh file-packet`). The receipt is his quote as recorded, not a signature; row 5 reads `ruled_by: operator`
  with a receipt as it always has.
