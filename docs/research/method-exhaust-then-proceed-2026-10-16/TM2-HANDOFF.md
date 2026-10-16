# truememory-2-0 under method v1.3: what to run

For the TrueMemory 2.0 program lead (pane research-kit-22), 2026-10-16. This session edited no truememory-2-0 record.
Method: `docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md` §13; research and receipts: `REPORT.md`
beside this file. truememory-2-0's frame has no `method_version` (reads 1.1): every v1.3 proceed path applies to it,
FAC-34..38 do not, and Stage 9 needs the operator's adoption (step 6).

Run everything from the program's records checkout under the program lease, as for any record write. First confirm
the live kit is v1.3: `scripts/research-kit/gate.sh read --help` lists `--practice`.

## 1. File row 15 as a scheduled read (the certificate stops waiting on v5)

The instrument pins `other` and `regex-matched` to v4 and leaves `regex-missed` and `pushback` awaiting v5, so the
read is not in grasp. Check that `router-heldout/instrument.json` maps both to `null`; if either is missing rather
than null, run `scripts/research-kit/heldout.py instrument --await regex-missed,pushback` first (it opens no set). Ruling `915d7fb98b7f`'s outer bound is v5 ready about Nov 24 plus its 7-day cap, so the due is
the ruling's own date, not a guess:

```
cc-research read file --program truememory-2-0 --row 15 \
  --awaits "v5: seal at 400 unused regex-missed candidates, read at 40 labeled subtle re-asks (ruling 915d7fb98b7f)" \
  --owner "truememory-2-0 lead" --due 2026-12-01 \
  --falsifier "grep -q '\"event\": \"read\"' <records dir>/scheduled-reads.jsonl" \
  --why "v5 accrues from about Nov 4; no route in grasp makes it exist sooner" \
  [--blocks-wave <each wave whose behaviour depends on the router, if any>]
```

Name a `--blocks-wave` only for a wave that builds on the re-ask router's labels; the router is kit infrastructure,
so most TM2 waves rest on none. Commit the records (row 12 fails a dirty tree).

## 2. Re-file the six not-yet-true premises with keyed dues (optional, recommended)

Their current dates (W1 2026-12-31, W2 2027-01-31, W5 2027-03-31) stay valid, but they are guesses that the program's
own waits already moved once. Re-file each with every flag it was filed with (lead notes, "FILING DRAFT"), changing
only `--due` to its owner wave plus the wave's expected length, for example:

```
cc-research premise file --program truememory-2-0 --refile --id PR-17 --awaits build --owner-wave W1 \
  --owner <as filed> --closing-probe P-NYT-PR17-W1 --due W1+45d --why "<as filed>; due keyed to W1's start (v1.3)"
```

PR-18, PR-43 and PR-80 key on `W1+45d`, PR-63 on `W2+45d`, PR-54 on `W5+45d` (pick N per wave). A key may name only
the owner wave, a wave resting on the premise, or `cert`.

## 3. The certifying run

`scripts/research-kit/gate.sh run --program truememory-2-0` (no read consent needed now). Expect rows 1–14 and 16–19
PASS or FILED as on the 13:09Z plain gate, and row 15 FILED with "nothing decrypted, no read logged". The run writes
`CERT-v<n>` and moves the registry to `certified`. Its `Scheduled checks:` line now also counts the waits filed after
the freeze (seven, all found late: the six premises and the read).

## 4. The operator signs the certificate (new: waves wait for it)

v1.3 refuses every build wave until the operator's valid signature pins the newest certificate (decision
`1d192ef8961e` asks whether to keep that; it is built and live). Hand over:

```
cc-signoff research:truememory-2-0/cert --evidence <path of the CERT-v<n>.md you read>
```

## 5. Fire build waves as before

`handoff-fire.sh --requires-gate truememory-2-0 --gate-wave <W>` now records the wave's start, so dues keyed to it
begin counting. `gate.sh requires --program truememory-2-0 --wave <W>` previews the verdict.

## 6. Adopt Stage 9 (operator, recommended)

The ~205 forecast changes after signoff need a counted home that is not a take-back; Stage 9 is it. Hand over:

```
cc-signoff research:truememory-2-0/adopt/stage9 --because "certify what the build produces before calling it done"
```

After the last build wave: `gate.sh built-freeze --program truememory-2-0 --artifact <abs dir> --wave …`, then the
Stage 9 instruments and `gate.sh built-run` (skill, Stage 9).

## 7. At v5: the read

Seal and label v5 as ruled, pin it (`heldout.py instrument --pin regex-missed=v5,pushback=v5`), run a fresh freshness
pass, then practice until it prints `PRACTICE READY` (it decrypts nothing and writes nothing):

```
CC_RESEARCH_ROUTER="$PWD/scripts/research-kit/router.py classify" scripts/research-kit/gate.sh read --program truememory-2-0 --row 15 --practice
```

Then spend the read detached:
`. scripts/lib/detach.sh; CC_RESEARCH_ROUTER="$PWD/scripts/research-kit/router.py classify" detach /tmp/tm2-read.log scripts/research-kit/gate.sh read --program truememory-2-0 --row 15 --consent-sealed-read`.
A PASS clears any `--blocks-wave` waves; a FAIL is final for those items and keeps them held.

## 8. The frame-omission row due 2026-11-02T03:11Z

The sweep now spares it as soon as the operator re-signs the frame after the row was held, before the due as well as
after; a later passing gate run closes it. So the frame-delta cycle can run now instead of after Nov 2.
