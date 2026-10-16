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
  Decision `55e7da1e7311` (2026-10-16) adds `not-yet-true`, written only by `cc-research premise file`:
  `{id:"R-NYT-PR-n", why_unreachable:"not-yet-true", premise, awaits:"build|upstream-merge|third-party-answer",
  owner_wave, owner, due, closing_probe, blocks_waves:[..], why, ts}`. Gate row 11 also needs `premise`, `owner` and
  `awaits` on it, and fails a row filed at or after its premise was refuted. A refile (`premise file --refile`) writes
  the k-th filing of a premise as `R-NYT-PR-n-rk` (`-r2` for the first refile) with `supersedes:"<old id>"` and appends `{id:<old id>, superseded_by:<new id>,
  superseded_why, ts}` to the old one, which stays as history. Every reader (`kit.not_yet_rows`; gate rows 4 and 11,
  `gate.sh requires`, the certificate's scheduled checks) takes the newest live filing and skips a superseded one;
  row 11 lists it `superseded by <new id> (history)` and fails it only when that id is not a refile of it for the same
  premise.
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
    `--probe <probe id>` repeated joins recorded probes to the premise, so `kit.premise_level` (gate row 4) counts them:
    it writes `probes` as the folded list plus the new ids, de-duplicated. It is refused for a probe id absent from
    `probes.jsonl`, for one whose `closes` does not name the premise (record it with `probe-run.sh run --closes PR-n`),
    and when every id is already joined and nothing else is revised. It never writes `verdict`.
  - Gate row 4 asks that a refuted premise's `DR` dependents be revised (ruled, reopened, carried or descoped) at or
    after the ts of the event that set `verdict` to `refuted`, not the folded ts, so a later re-check or revision
    event does not re-open them.
  - `cc-research premise file --id PR-n --awaits build|upstream-merge|third-party-answer --owner-wave W --owner <who>
    --due <ISO|YYYY-MM-DD> --closing-probe P-.. --why "<reason>"` (optionally `--blocks-wave W` repeated) files a
    load-bearing premise below its required level as not-yet-true (decision `55e7da1e7311`): it appends the
    `residual.jsonl` row above and `reconcile.jsonl` `{id:"residual:R-NYT-PR-n", disposition:"filed", ref}` (gate row
    12). It writes nothing to `premises.jsonl`. It refuses whatever gate row 4 would fail, with the same reasons
    (`gate_rows_a.not_yet_problems`): a premise id absent from `premises.jsonl`; a refuted, already-at-level or
    non-load-bearing premise; a verdict other
    than `partial` or `holds`; an `awaits` that cannot raise the premise's `truth_lives_in` (`build` raises `behavior`
    and `target-env`; `upstream-merge` adds `live-state`; `third-party-answer` adds `operator`; `code` and `document`
    are read now and never filed); a due date that is unparseable or past; a prose `recheck_cmd`; a dependent that is
    not a `DR` decision carried (a well-formed set or a class-C packet) or ruled by the operator or a packet default;
    an owner wave, a dependent's narrowing wave or a dependent's `blocks_waves` member that any decision or known row
    descoped; no wave resting on it (the filing's `--blocks-wave` plus its dependents' `blocks_waves`, less the owner
    wave); and a second filing for the same premise unless `--refile` is given.
  - `cc-research premise file ... --refile --why "<reason>"` (the same flags, every one re-stated) supersedes the
    premise's live filing, to re-date it before its due date passes or to move its owner, owner wave, closing probe,
    awaited event or blocked waves. It writes the new row and the old row's `superseded_by` event (shapes above) and the
    new row's reconcile line, and it refuses everything a first filing refuses, judged on the new row (a past `--due`
    included; the old row's own state does not matter), plus `--refile` for a premise with no live filing.
  - Gate row 4 reports such a premise FILED, naming its level, owner wave, awaited event, owner, due date and closing
    probe, while every guard above still holds now; the moment one breaks, the filing FAILs naming why. `gate.sh
    requires --wave W` refuses each wave resting on a filed premise until its closing probe has run with exit 0 and is
    joined (`premise revise --id PR-n --probe P-..`); the owner wave, which runs that probe, is never refused by it. If
    the joined probe refuted the premise, those waves also wait until its dependents are revised.
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

- `courier.sh preflight` → `<sealed>/preflight.json` `{vendor:{binary, ok, model_id, error}}`, the latest run
  (open-round reads it for freshness), and appends every run to `<sealed>/preflights.jsonl` `{ts, lanes:{vendor:{...}}}`
  (added 2026-10-13); exit 3 if any lane dead. Gate row 13 passes on any recorded run that is all-live (or meets the
  frame's "two vendors" rule) with every `at` strictly before `contract_page_at`: `preflight.json`, a `preflights.jsonl`
  line, or the "Vendor preflight" lines of `CONTRACT.md` when its sha256 equals `contract_page_sha256` (a mismatch fails).
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
  `cc-research decision rule` does, so gate row 5 passes the ruled reversible row. A decision the sweep converted and
  the operator then answered gets its waves back and no default ("An answer after a sweep conversion", below).
- `gate.sh requires --program P [--wave W] [--json]` (`lib/gate_requires.py`) → exit 0 the build wave may fire, 1
  refused with each reason, 2 the program cannot be read. Reads the newest certificate and the LIVE decision and
  known-row records (the sweep and the frame-delta cycle clear blocks after the certificate). The reader behind
  `handoff-fire.sh --requires-gate P --gate-wave W`.

## Settling a round (`lib/settle.py`, verbs on `round.sh`; added 2026-10-11)

Before any plan edit, a closed certification round's holes can be settled honestly, seed-blind for the lead. Every
verb runs under the program lease, appends events to `holes.jsonl` (the fold keeps the newest), and refuses with
exit 2. `--evidence` files must sit inside the records dir (gate row 8 fails a record citing `/tmp`). Row 8's `/tmp` scan of
`holes.jsonl` skips text vendors wrote verbatim (`gate_rows_a.HOLE_VENDOR_TEXT`: `verification.probe|consequence|read`,
`materiality.note`, and a blind raise's `claim`, `title` and `locus.quote`; added 2026-10-13) and scans every lead field. `by` is
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

### Settling the last round, and naming the cap round's finds (added 2026-10-12; REPORT.md §3.8)

"The cap round is verification-only. Its finds are listed on the certificate as named known rows applied in build
wave 1, and the plan is not edited." Closing the last round (R_max spent or the stop rule fired) used to close the
`certification-round` activity at once, before its settle steps could run under it.

- **What the last round owes** — `round.py settle_owed`, the one predicate `round.sh close`, the settle verbs and
  `gate.sh cert-activity` all read: once the newest certification round has closed, (1) its rating re-pass, while
  `m["kappa"].materiality` is below `kappa.below` and `kappa.repass` is false; (2) each of its CONFIRMED MATERIAL
  holes that counts as new material (`kit.not_new_material` is false) and that no known row names: a clause-(g)
  one is held (`round.sh hold-g`), and in a verification-only round any other one is named (`round.sh name-cap`).
- **The activity** — with no round due, close keeps the open `certification-round` row while anything is owed and
  sets its `settle_round` to that round: SETTLE-ONLY. `hold-g`, `refind`, `name-cap` and `repass` (through its
  re-close) re-read what is owed, and the last one closes the row. If the row was already closed (a round closed
  before this fix), `gate.sh cert-activity --program P` re-opens it settle-only, printing `settle-only: round K
  owes …` on stderr and the id on stdout; it refuses when nothing is owed ("round K owes no settle step") and while
  a front-end return is open. A due round clears `settle_round` (freeze, cert-activity, close).
- **What settle-only lets through** (router.py `open_settle_rounds`): under `CC_RESEARCH_ACTIVITY=<id>`, `round.sh`
  with a ROUND_SETTLE verb (artifact, split, verify-split, reproduce, hold-g, refind, repass, name-cap), `round.sh
  close --round K --reclose`, `courier.sh run --round K --role rater|verifier`, and a read-only `codex exec`.
  Nothing else: no `round.sh run`, no plain close, no `courier.sh bundle`, no reviewer slot, no other round's slot,
  no tagged Agent or Workflow. `round.sh run` past R_max stays refused by the kit as before.
- **Name a cap-round find** — `round.sh name-cap --program P --hole H --known-row KR-<n> --wave W --reason T
  --evidence F…` appends `{id: KR-<n>, kind: "cap-round", hole: H, round, applied_in_wave: W, blocks_waves: [],
  status: "open", named:{at, by, reason, evidence}}` to `known_rows.jsonl`. Refused unless H is a hole of a
  verification-only certification round that has closed, CONFIRMED MATERIAL, neither an artifact nor a split-off,
  not seed-tagged, not a re-find of a held hole, and not rated under clause (g) (that is `hold-g`'s); refused for a
  hole already named by any known row, a known-row id that exists, and a wave id that is not `[A-Za-z0-9][A-Za-z0-9._-]*`.
  The bundle withholds its evidence like a held row's (courier.py `settle_evidence`).
- **What a cap-round row blocks: nothing.** `blocks_waves` is empty, so `gate.sh requires` never refuses a wave on
  it (gate_requires.py reads `blocks_waves` for every open known row). A frame-omission row blocks its waves because
  the frame they build from is wrong until the frame-delta cycle re-signs it; a cap-round find is a known defect of
  a plan whose frame is sound, and its fix IS the work of the wave it names (`applied_in_wave`). Blocking that wave
  would deadlock the fix, and blocking later waves would add a gate the method does not ask for. The certificate
  still lists it under "Known rows", and gate row 1 notes it as open.
- **Gate row 9** fails a cap-round or rehearsal MATERIAL hole that no known row names, now less a seed catch, an
  artifact or unverified split-off and a re-find of a held hole (`kit.not_new_material`): the same selection as
  close's `new_material` and `estimate.counted_holes`.

### Rehearsal finds (added 2026-10-13; REPORT.md §3.8 "Rehearsal")

"A verified material find becomes a named known row." The rehearsal runs once, after the stop and before issue,
and never edits the plan. Its blind frame sessions' finds go through four `round.sh` verbs (`lib/rehearsal.py`),
each under the program lease. **The choice: a reserved round of the round machinery, not a path of its own.** The
finds live in the reserved round id `rehearsal` (hole ids `H-RH-<n>`, panels, briefs and `attempts.jsonl` under
`rounds/rehearsal/`, the bundle at `<sealed>/rounds/rehearsal/bundle/`), so they use the hole ledger, the
courier, the certification round's rater assignment and panel checks, and `known_rows.jsonl` exactly as a round's
finds do, and every round count skips them for free: `rounds/rehearsal/` never holds a `matrix.json`, and round
`rehearsal` matches no certification, built or delta id (round close, `estimate.counted_holes`, seed match and
the gate's round rows select rounds by matrix or by round number). No verb here opens a fix cycle or a freeze.

- **Raise** — `round.sh rehearsal-raise --program P --frame F --path PLAN --lines L --quote Q --claim C [--names
  ROW…] [--receipt T]` appends `{id: H-RH-<n>, event: "raise", round: "rehearsal", source: "rehearsal", raised_by:
  {frame, blind: true, by, at}, claim, names, locus:{path, lines, quote, numbering: "real"}, plan_blob, receipt?}`.
  Refused before the stop (no certification round has run, the last one is open, or `round.certification_due`
  says one is still due), for a frame that is not a `reask_map` frame with an axis, when the plan is not frozen or
  its blob differs from `freeze.json` `plan_blob`, for a path that is not the real plan, a quote not on the cited
  lines, and an empty claim. Gate row 8's `/tmp` scan skips the session's claim, receipt and quote, as it skips a
  blind reviewer's (`gate_rows_a.HOLE_BLIND_RAISE_TEXT`).
- **Verify** — `round.sh rehearsal-verify --program P --hole H-RH-<n> --vendor V` builds the reserved round's
  bundle of the REAL plan once (`courier.sh bundle --round rehearsal`), writes `briefs/H-RH-<n>-verifier.txt` (the
  frozen `skills/research-program/briefs/verifier.md` verbatim, then the finding under the neutral fid `f1`: a hole
  id would tell the verifier where it came from), and runs `courier.sh run --round rehearsal --pid H-RH-<n>-verifier
  --role verifier`. The panel is checked as `check-round` checks one (`cli_cert.panel_breaches`: pin, effort,
  integrity); a dead, void or verdictless panel records nothing (exit 3 or 4) and may be re-run within the slot
  re-run cap. Appends `{id, event: "verify", verification:{status, against: "real", plan_blob, by, vendor, panel,
  read, consequence, probe, at}}`. Refused for a hole that is not a rehearsal find, one already verified, a vendor
  that is not a live lane, and a plan that changed since the raise.
- **Rate** — `round.sh rehearsal-rate --program P --hole H-RH-<n>` runs the three raters of `cli_cert.raters` (rater
  1 non-Anthropic, rater 2 another family, rater 3 the third; the two-vendor default's fresh-process rater 3 too) on
  the frozen `briefs/rater.md` (RUBRIC.md), pids `H-RH-<n>-rater<k>`, in parallel through `courier.sh run --role
  rater`. Only a CONFIRMED hole, once. A lost rater records nothing and the re-run runs only the raters without a
  valid call. A rater lost past its re-run cap never runs again: when it is the only one lost and the other two
  agree, no call of it moves the median, so their level is recorded with `materiality.lost: {slot, vendor, why}`
  and only their two calls in `raters`; otherwise the rate is refused. Appends `{id, event: "rate", materiality:{level, clause, raters:{"1"|"2"|"3": {rating, clause, vendor,
  panel}}, at}}`: the level is the median call (M > R > C > G), so MATERIAL is 2 of 3 M, the rule `round.sh repass`
  checks; the clause is the one most material calls gave, the earlier rater on a tie. The verifier already
  reproduced the consequence, so a material level is MATERIAL, never MATERIAL-DISPUTED. Rater notes stay in the
  panels' raw output, not the ledger.
- **Name** — `round.sh rehearsal-name --program P --hole H-RH-<n> --known-row KR-<n> --wave W --reason T --evidence
  F…` appends `{id: KR-<n>, kind: "rehearsal", hole, round: "rehearsal", frame, applied_in_wave: W, blocks_waves:
  [], status: "open", named:{at, by, reason, evidence}}` to `known_rows.jsonl`: a row applied in build wave W (W1
  by the method) that blocks no wave, for the reason a cap-round row blocks none. Refused for a certification
  round's hole (that is `name-cap`'s or `hold-g`'s), a hole that is not CONFIRMED MATERIAL, a clause-(g) find
  (`round.sh hold-g` holds it for the frame-delta cycle, as a round's), a hole already named, a known-row id that
  exists and a bad wave id. The bundle withholds the row and its evidence from any later round
  (`courier.HOLE_ID` reads `H-RH-<n>` too).
- **Gate row 9** fails a rehearsal hole that no known row names and that is not yet verified, or verified
  CONFIRMED and not rated, and, as before, a MATERIAL one left unnamed. A REFUTED, CONTACT or below-material find
  passes. Each `H-RH-<n>` still needs its `trace.jsonl` row (gate row 8), to its known row or a recorded rejection.
- **Where they run.** None of the four is in router.py `ROUND_SETTLE`, and `courier.sh run --round rehearsal` is
  no settle round's slot, so a session inside the program root gains nothing under a certification-round or
  settle-only tag. They run under the rehearsal activity's tag (next section; added 2026-10-16), or from an
  allow-all turn outside the root.

### The rehearsal activity and the relay trials (added 2026-10-16; method packet beb0f1a6de53, "agent-run")

An agent runs the whole rehearsal (REPORT.md §3.8: the blind lens sessions, the 20-trial relay test, at least one
trial from a pane outside the program's directory), so gate row 14 can pass without the operator typing.

- **`gate.sh rehearsal-activity --program P`** prints the open `rehearsal` activity's id, opening one if none is
  open (`lib/gate_cert.py` `cmd_rehearsal_activity`; the row carries `opened_at` and `attempt`). Refused unless the
  registry reads `certifying`, `freeze.json` exists, the newest certification round is closed and none is due (the
  stop rule or R_max), that round owes no settle step (`round.py` `settle_owed`), no front-end return is open, and
  `rehearsal.jsonl` holds no pass and fewer than 2 records. `round.sh close` prints it as the next step when it
  closes the certification-round activity on the stop.
- **What the tag unlocks, while `certifying` only** (`router.py` `REHEARSAL`): `CC_RESEARCH_ACTIVITY=<id>` on
  `cc-research rehearse trial|record`, on `round.sh rehearsal-raise|rehearsal-verify|rehearsal-rate|rehearsal-name`
  and on `courier.sh` with `--round rehearsal` only; `[activity:<id>]` in an Agent, Task or Workflow input (the
  lens sessions). Nothing else: no other round verb or round, no vendor CLI, no `claude -p`, no other buying verb,
  and nothing once `certified` or on a relay turn. `handoff-fire.sh` stays denied under this tag as under every
  other (operator ruling 2026-10-11), and so does a bare terminal launch of `claude` (`kitty @ launch … claude`,
  `it2 session split … claude`) on every turn that is not allow-all. `cc-research rehearse frames` is a read and
  passes on any non-relay turn.
- **`cc-research rehearse trial --program P --phrase TEXT [--where root|outside] [--name N] [--timeout S]`**
  (`lib/rehearse_trial.py`) runs ONE trial. The phrase must be one of §3.8's four, verbatim (`RELAY_PHRASES`), or
  a `reask_map` frame with an axis; the cwd is the program's first `cwd_root`, or (`outside`) this kit's own
  checkout, refused if it lies inside any root; only an outside trial carries the suffix ` (about the research
  program <N>)`, N the slug or a registered alias (default: the first alias). It opens a kitty tab (`--keep-focus`)
  running `zsh -ilc 'claude --session-id <uuid> <prompt>'` with `CLAUDE_CONFIG_DIR` pinned by `--env`, so the
  phrase is the pane's first and only prompt: no `HANDOFF-ENGAGE`, back-channel block or `Goal set:` line, and the
  router classifies it as a genuine prompt. It waits for the turn to end (a reply, no unanswered tool call, the
  transcript quiet for `CC_RESEARCH_TRIAL_SETTLE_S`, default 20 s, so a Stop-check block extends it), reads the
  transcript from `<CLAUDE_CONFIG_DIR>/projects/*/<uuid>.jsonl` and the label from `route-state/<uuid>.json`, closes
  the pane from outside, and appends `{trial, prompt, phrase, where, cwd, reply, replies, tools, label, session_id,
  config_dir, transcript, window_id, closed, timed_out, attempt, at, trial_routed}` to
  `<records>/evidence/rehearsal/trials-<attempt>.jsonl` (refused past 20). `reply` is every reply text of the turn
  joined, so a repaired second reply counts against the line budget. Refused without an open rehearsal activity,
  outside `certifying`, or when the pane's account has not trusted the cwd. Exit 1 on a timed-out trial. Exempt from
  the lease (`lib/cli.py` `LEASE_EXEMPT`, with `rehearse frames`): it writes no record.
- **How the router knows a trial (added 2026-10-16).** Before the pane starts, `rehearse trial` marks the uuid it
  passes to `--session-id` in `<research home>/route-state/trials/<uuid>.json` (`router.trial_mark`: `{program,
  attempt, phrase, where, at}`, reaped with the route records after a week). The router reads the session id every
  hook receives, never the prompt or the pane's environment. A marked session routes a research order ("if more
  research moves your conviction, do it now") with the certified rules plus the relay, whatever the registry state:
  the certificate state lines in its context, every tool blocked but the certificate read (`cert_read`), and the
  Stop relay check (`router.relays`). Without it a certifying program lets a research order run the kit's rounds and
  any other non-research tool, so the relay could not pass before certification while row 14 must pass for it. The
  mark only narrows a session's rights; nothing changes for an unmarked session. The route record carries `trial:
  true`, and the trial row `trial_routed`.
- **`rehearse record`** without `--trials` reads that attempt's file, and fails a trial the router labeled anything
  but `completeness`, `pushback`, `research-order` or `unavailable` (the relay never ran: an allow-all label is the
  risk the skeptic named for "if more research moves your conviction, do it now") or one that timed out, on top of
  the checks above. A research-order trial is judged as a completeness relay: the lines unchanged, no relay
  violation, every tool a certificate read.
  It closes the rehearsal activity on a pass or a failed re-test. It still takes the lease. Gate row 8's `/tmp`
  scan skips a trial row's `reply`, `replies` and `tools` in `trials-<n>.jsonl` and `practice.jsonl`, and the
  `trial <n>: …` lines of `rehearsal.jsonl`'s `fails` that quote them (`gate_rows_a.py` `TRIAL_OBSERVED_TEXT`):
  they record what the observed session said and ran, and every other field is still scanned.
- **`rehearse trial … --practice` (added 2026-10-16, before truememory-2-0's re-test).** The same trial (pane,
  launcher, `trial_mark` with `practice: true`, router, Stop relay check, transcript read), appended with `practice:
  true` to `<records>/evidence/rehearsal/practice.jsonl`, uncapped, and printing its own verdict as `fails`
  (`cli_cert.trial_fails`, what the record holds each trial to). `rehearse record` refuses that file, any row
  carrying `practice`, and `--practice` itself; gate row 14 reads only the record. Refused when a counted trial is
  (no open activity, not certifying) and once the relay test is settled (`attempt_of`). It writes no record: the
  last re-test is never spent on hope.
- **The certificate read a relay turn is told to run (2026-10-16).** `router.cert_cmd`: this kit's `gate.sh` by
  absolute path, in the relay context, the block's deny and the Stop check's re-answer, because a program's root is
  usually another repo with no `scripts/research-kit/` (run 1's relative read exited 127 in four trials).
  `cert_read` allows it bare or through `bash`/`/bin/bash`, the same read. The relay context also tells the reply to
  open with the lines, since the check reads the first line as the verdict, and names the phrases the check reads as
  an added item (`router.ITEM`: "still open", "except", …), since two of nine practice trials called the program
  "still open". No relay rule changed. A relay turn's passing reply makes
  `relay-check --relayed-rc 3` exit 3, and `hooks/completion-assert.sh` then abstains from its other arms: none
  can be obeyed with every tool blocked. Run 1's 43 failures, each with its cause:
  `docs/research/rehearsal-relay-run1-causes-2026-10-16.md`.
- **The orchestrator's sequence:** `gate.sh rehearsal-activity` → the lens sessions (`[activity:<id>]` Agents or the
  rehearsal Workflow, one per `rehearse frames` frame) → 20 `rehearse trial`s, one `--where outside` → read the rows
  → `rehearse record --frames-typed <the frames run>` → for each material find, `round.sh rehearsal-raise`, then
  `-verify`, `-rate`, `-name`, all under the tag. `workflows/rehearsal.workflow.js` (args `activity`, `record`)
  runs the first three steps, and the record with `record: true`.

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
(`router.py` `CC_RESEARCH_BUYING`): `reopen`, `extra-round`, `round`, `frame-critique`, `rehearse` (`rehearse
frames` is a read and passes; `rehearse trial|record` pass under the rehearsal activity's tag).

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
  Refused unless the decision is `ruled` or `carried`, and once its `reopened` events number 2 (one cap per decision,
  whichever state each reopen left). While `reopened`, gate row 5 fails on it and `gate.sh requires` blocks its
  waves; it leaves that state by his re-ruling (below) or by `decision carry`.
- `cc-research decision rule --program P --id D --chosen <option> --by operator --receipt "<his words>"
  --revisit-trigger "<trigger>"` appends `{status: "ruled", ruled_by: "operator", chosen, receipt,
  revisit_trigger}`. No 90 rule applies; both `--receipt` and `--revisit-trigger` are required. Refused unless the
  decision is `reopened` with `reopened_by: "operator"`: an open decision still goes to him as a packet
  (`gate.sh file-packet`). The receipt is his quote as recorded, not a signature; row 5 reads `ruled_by: operator`
  with a receipt as it always has.

### Revising a carried decision: `cc-research decision carry`

Gate row 4 asks that every `DR` dependent of a refuted premise carry an event with status ruled, reopened, carried or
descoped dated at or after the refutation. For a carried decision whose set still stands, no other verb writes one:
`decision reopen` would leave row 5 failing, and `gate.sh file-packet` appends only `packet`.

- `cc-research decision carry --program P --id D --because "<what changed>" --receipt "<the operator's words>"
  [--set FILE]` appends `{status: "carried", carried_by: "operator", carried_because, carry_receipt, carried_at,
  set}`, dated now. It rules nothing and never writes a conviction. Both `--because` and `--receipt` are required;
  the receipt is his quote as recorded, not a signature.
- Without `--set` it re-affirms: the event copies the folded `set` unchanged, and is refused when that set is not
  well-formed. `--set FILE` replaces it with the JSON object in FILE, `{members: [{label, feasibility_probe, ...}],
  narrowing_probe: {wave, owner, due, ...}, revision_budget_h}`. Either way the set must pass the check gate row 5
  makes (`kit.carried_set_ok`, the one predicate both use): 2-4 members each with a `feasibility_probe`, a
  `narrowing_probe` with `wave`, `owner` and `due`, and a `revision_budget_h`. A carried decision that stands on a
  dated class-C packet instead of a set is re-affirmed with no `set` field.
- Accepted for a decision that is `carried`, `ruled` or `reopened`; refused for an `open` one (it goes to him as a
  packet), a `descoped` one and an unknown id. A ruled or reopened decision has no set, so it needs `--set`, and the
  event writes `chosen: null` and `ruled_by: null`: the earlier ruling is withdrawn. A carried decision keeps its
  `ruled_by`.
- No gate row changed its verdict for this verb: row 4 already counted a `carried` event, and row 5 reads the set as
  before.

### An answer after a sweep conversion (added 2026-10-16)

When `gate.sh sweep` step 2 has converted a decision (an overdue class-C packet replaced by a class-B one on the
reversible option, the event carrying `converted_from` and `descoped_waves`), `decision rule` (either `--by`),
`decision carry` and `decision reopen` answer it (`cli_records.answer_conversion`). The verb first actions the converted
class-B packet in cc-decide if it is still open (evidence `answered by <verb> --by <who> <ts>`), so its default can never
fire over the answer, and refuses with nothing appended when cc-decide cannot be read or refuses. If the fold's
`descoped_waves` is non-empty, its event also writes `descoped_waves: []` and `restored_waves: [<the waves>]` and the
verb prints the waves it restored, so `gate.sh requires` stops refusing them as descoped (the decision's own status
still governs them). While the fold still names the converted packet, the event also writes `packet: null`, since gate
row 5 reads the folded packet and fails a class-B one on an irreversible decision. A decision the sweep never converted
gets none of these fields and no cc-decide call. Defense in depth: sweep step 1 does not apply an expired class-B
default when a rule, carry, reopen or affirm event follows that packet's conversion event, and prints
`default of <pkt> not applied: <D> answered at <ts> after conversion`.

- `cc-research decision affirm --program P --id D --because "<why it stands>" --receipt "<the operator's words>"`
  keeps a converted decision that is `ruled` or `carried` as it stands, without spending a reopen: it appends
  `{affirmed_by: "operator", affirmed_because, affirm_receipt, affirmed_at}` plus the fields above, and changes no
  status, choice or set. Refused, appending nothing, for an `open` or `reopened` decision (`decision rule` or
  `decision carry` answers those) and when there is no conversion left to take back.
- Sweep step 2 converts only an `open` or `reopened` decision. An overdue class-C packet on one already `ruled` or
  `carried` is actioned in cc-decide with evidence `decision already <status>; packet superseded`: no class-B packet,
  no descope, no record event.
