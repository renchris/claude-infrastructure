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
`registered → certifying (gate.sh freeze) → certified (gate.sh run, all rows pass) → closed`. A valid operator
`reopen` signature newer than the certificate makes `gate.sh run` set the state back to `registered`.

## Tracked records (fields the kit uses)

- `frame.json`: SYNTHESIS shape, plus `profile` (`lite|standard|full`), `deliverable_repo` (abs path),
  `reviewer_pins` `{anthropic, frontier, openai, google: model id}`, `rulings` `{definition_of_complete: {at, quote},
  exemption: {at, quote}}` (§3.1), `fac_map` `[{fac, row|null, na_reason|null}]` covering FAC-01..FAC-33, `reask_map`
  `[{frame, axis|null, excluded_quote|null}]`, `sources_required` `[source id]`, `populations` `[name]`,
  `known_rows` `[{id, kind:"frame-omission", names_rows:[], blocks_waves:[], resign_due, default:"descope|class-b",
  status:"open|closed"}]`.
- `acceptance.json`: `{"rows":[{id, predicate, check_cmd, threshold:{metric, op, value}, negative_branch,
  control:{known_bad, known_good}, soundness, residual_label|null}]}`.
- `decisions.jsonl`: SYNTHESIS shape. The lead writes `tally` `{premises:[PR ids], flip_probe:"P-..",
  flip_result:"negative|positive|null"}`, never `conviction`; `kit.conviction` derives it. `packet`
  `{id, class:"B|C", due:ISO}`; `ruled_by` `agent|ladder|operator|packet-default`; `status`
  `open|ruled|carried|reopened|descoped`.
- `premises.jsonl`, `sources.jsonl`, `census/<pop>.json`, `contact_matrix.json`, `residual.jsonl`, `trace.jsonl`,
  `holes.jsonl`, `changes.jsonl`: SYNTHESIS shapes. `residual.jsonl` `why_unreachable` adds the method-created classes
  `depth-cap`, `stage-budget-exhausted`, `stub-validated` (§10 item 7), each needing `owner_wave`, `due`, `closing_probe`.
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
  `extra-round` signature), refuses a third frame-critique round; writes `rounds/K/matrix.json`. Tests override the
  courier with `CC_RESEARCH_COURIER`.
- `estimate.py forecast` → JSON `{p50, p90, r_max, desk_mean, desk_n95, invisible_mean, p_any, quiet_streak,
  stop:"running|dry|cap"}` from `rounds/*/matrix.json`.
- `seed.py plant|apply|prescreen|match|status` → vault `<sealed>/vault/seeds.enc`, key from the keychain item
  `cc-research-seed-vault/<slug>` (tests: `CC_RESEARCH_VAULT_KEY`). `match` (run by `round.sh close` before quiet is
  computed) appends `{id, seed_match: <seed id>}` to `holes.jsonl` for each MATERIAL hole restating a seed's defect
  (span overlap + class + claim, not overlap alone); `prescreen --caught …` marks seeds a blind pre-screen caught
  `discarded`, so they are never planted; `status` prints a second line with seed realism beside real detection.
- `estimate.py forecast` also prints `found_raw`, `found` (deflated by `false_material_share`), `found_shadow`;
  `estimate.py calibration [--file]` prints coverage, bound sharpness and Spearman rank skill.
- `cc-research probe --id P-.. --kind K --closes PR-.. -- <cmd…>`, `cc-research doctor` and `cc-research self-test`
  (each acceptance row over `control.known_bad`/`known_good`, fixture in env `FIXTURE`, as gate row 6 runs it);
  `probe-run.sh run|doctor` is a bash 3.2 shim onto the first two.
- `gate.sh register|freeze|run|render|sweep|file-packet|requires|close` (see `lib/gate.py`).
- `gate.sh requires --program P [--wave W] [--json]` (`lib/gate_requires.py`) → exit 0 the build wave may fire, 1
  refused with each reason, 2 the program cannot be read. Reads the newest certificate and the LIVE decision and
  known-row records (the sweep and the frame-delta cycle clear blocks after the certificate). The reader behind
  `handoff-fire.sh --requires-gate P --gate-wave W`.

## `bin/cc-research` (wave 2, REPORT.md §8 items 9–12 and 15)

`bin/cc-research <verb>` → `lib/cli.py`, which lists the module owning each verb. It reads and writes the records
above and nothing else; the kit scripts stay as thin compatibility entry points over the same modules. Verbs that
read one program take `--program P` (`verdict` also takes the slug positionally: `cc-research verdict <slug>` is the
certificate read the research block whitelists, `router.py` `cert_read`). Names the block treats as buying verbs
(`router.py` `CC_RESEARCH_BUYING`): `reopen`, `extra-round`, `round`, `frame-critique`, `rehearse`.

Cross-module contracts (a consumer depends on exactly these shapes):

- `cc-research verdict [--program] P [--json]` → the `gate.sh render` state lines, then an operator block (pending
  concerns, "waiting on you since <date>", the priced menu). `--json`: `{program, state, lines:[…],
  pending_concerns:N, waiting_since:ISO|null|"unknown" (null: nothing open; "unknown": cc-decide unreadable), menu:[{id, label, price, effect}]}`.
- `cc-research pending --json` → `{programs:[{program, state, pending_concerns, waiting_since, menu:[…]}]}` over every
  registry program not `closed`. Read by `hooks/operator-readout.sh` and `scripts/wrap-ledger.sh`.
- `cc-research concern add --program P --text T [--raised-by operator|agent|sweep|build|rehearsal]` appends a
  `challenges.jsonl` row with `triage: "pending"`; `cc-research concern list --program P [--pending] [--json]`.
- `cc-research triage --program P` buckets pending challenges by the §5.2 table through a blind rater, appending
  triage events to `challenges.jsonl` (and `changes.jsonl` for counted buckets), and is the writer of
  `$CC_RESEARCH_HOME/activities.json` (`lib/activities.py`; shape in `router.py`'s header).
- `cc-research job sweep|freshness|triage|drift|market [--program P]` → one scheduled pass (no `--program`: every
  registry program in `certifying|certified`). The launchd runners in `scripts/research-kit/jobs/` call only this.
- `cc-research reference-class record|show|check` → `docs/research/research-reference-class.jsonl` in
  claude-infrastructure (append-only).
