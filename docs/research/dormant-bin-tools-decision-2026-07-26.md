# DORMANT-7 bin tools — decision

**Item:** cc-backlog `52b235d4009b` · **Source:** audit02-deadbin 2026-07-25 · **Decided:** 2026-07-26

> "cc-idl sealer inert (93% of IDL unsealed — tamper-evidence guarantee void),
> cc-wait/cc-run/cc-respawn/cc-route/cc-bind/cc-digest built+gate-attested+never invoked —
> **wire callers or retire gates**"

---

## Verdict

**One tool was broken, one was never dormant, and five are episodic by design.** The framing
"wire callers or retire" assumed a single defect class; the evidence shows three.

| Tool | Effect-read (durable artifact) | Verdict |
|---|---|---|
| **cc-idl** | chain frozen 2026-07-19 at 6,910 links; `verify` → **rc 7** | **WIRE + FIX** — the one real defect |
| **cc-route** | `~/.claude/route/route.jsonl` — 187 records, **9 that day** | **NO ACTION — audit claim refuted** |
| **cc-wait** | `~/.claude/wait-contracts/` — 62 contracts (Jul 14-15) | **KEEP** — episodic, real prior use |
| **cc-bind** | 1 ruling + **8 `Acked-Ruling:` trailers** in git history | **KEEP** — episodic, real prior use |
| **cc-digest** | `~/.claude/autonomy/digests/` — 2 digests (Jul 18-19) | **KEEP** — see §4 |
| **cc-respawn** | none | **KEEP** — lead-invoked; its own gate says "activation-free" |
| **cc-run** | none | **KEEP** — agent-invoked wrapper |

**Nothing is retired.** One tool is wired, and the gates are corrected so dormancy is visible
rather than hidden behind a green check.

---

## 1. The audit's oracle was wrong, and that is the transferable lesson

The audit graded dormancy by **grepping for call sites**. On that oracle `cc-route` reads dead:
whole-repo grep finds no invocation, no launchd job runs it, nothing in the live hook layer
mentions it. It had also been run **nine times that day**, and 187 times since Jul 16.

These are **agent-invoked CLIs**. An agent reaching for a tool at the moment it needs one leaves
no call site behind. For this class of tool, "no caller in the repo" is the expected state, not
evidence of death — so a grep-based sweep produces a false positive on every healthy episodic
primitive, and the recommended remedy (retire it) would have deleted working tooling.

The sound oracle is the **durable artifact** each tool writes — the same effect-read discipline
already used elsewhere in this repo to prove liveness from products rather than surface state.
Every row in the verdict table above is an effect-read, not a grep.

A second-order caution, found while wiring the readout: the oracle must live **outside the
working tree**. `cc-bind` writes to the tracked path `docs/rulings/`, whose mtimes are set by
`git checkout` — reading it reports "used today" on any fresh clone. Its true last-use comes
from the `Acked-Ruling:` commit trailers, which carry their own timestamps.

## 2. cc-idl — the one real defect (and it was worse than "inert")

`cc-idl` keeps a tamper-evident hash chain over the autonomy IDL in a sidecar. The chain is
**append-only and monotonic** — the immutability of its sealed prefix *is* the security property,
because it is what stops an attacker laundering an edit by re-sealing. The IDL, meanwhile, is
**size-rotated** hourly by `rotate-autonomy-logs.sh`.

Nobody owned that seam. `cc-idl seal` had **zero callers**, so the chain froze on 2026-07-19 at
6,910 links while the IDL rotated three times beneath it (archives dated Jul 19, Jul 23, Jul 26).

The live reading at decision time:

```
$ cc-idl verify
TAMPER: idl.jsonl has 119 line(s) but the chain sealed 6910 — 6791 sealed record(s) DELETED/TRUNCATED
$ echo $?
7
```

This is **not** the "unsealed, guarantee void" state the audit recorded. It is a **detector stuck
ON**: `verify` reported catastrophic tampering permanently, on every invocation, as an artifact of
routine rotation. That is strictly worse than an unsealed log — an alarm that always fires is an
alarm nobody can read, and it makes a *real* tamper indistinguishable from a Tuesday.

The audit's "93% unsealed" was a snapshot of the same drift caught mid-slide; earlier audits
recorded 98.1% (a10, 2026-07-22) and a 6,910-vs-1,304 split (session-crash-forensics #9). All
three are the same frozen chain measured against a moving substrate. Prior research had already
framed the fork — *"wire a rotation-epoch re-seal or retire the chain"* — and left it open.

### The fix: rotation epochs (landed)

`rotate-autonomy-logs.sh` now owns the seam. It is **already a loaded hourly launchd job running
a symlink into this checkout**, so this required no new activation and no C10 step:

1. **Periodic seal** — every run seals the IDL tail. This is the caller `cc-idl seal` never had;
   sealing now tracks the job's cadence instead of the rotation threshold. Best-effort by
   construction: a seal failure is recorded in the run record and never fails the rotation,
   because bounding unbounded growth outranks sealing it.

2. **Rotation epochs** — a rotation *closes* an epoch instead of desyncing the chain: seal first
   (so the archived sidecar covers the archived body completely), archive the sidecar at the
   **same stamp** as the body it seals, and open the successor with an `idl_epoch_close` record
   naming the retired `{seq, head}` — itself sealed into the new genesis chain. The epochs form
   one continuous **chain-of-chains**: deleting an archive stays detectable, and re-genesis is
   witnessed instead of silent.

Chains are **retired, never deleted**. Deleting a chain and re-sealing from genesis is precisely
the one residual erase `cc-idl`'s `head` verb exists to witness.

### Anti-launder — why the repair is not automatic

An orphaned chain (chain longer than the live IDL) is exactly what a **real truncation attack**
looks like. The tool cannot distinguish it from a pre-wiring rotation artifact, so auto-healing on
sight would hand an attacker a laundering path: truncate the IDL, wait for the sweep, walk away
clean.

Therefore:

- The legacy orphan is cleared **only** by an explicit `--repair-chain-epoch`, which **refuses**
  when the chain is not orphaned (a same-length hash divergence is a real tamper and stays loud),
  and which **records the orphaned head into the successor epoch** rather than discarding it.
- A rotation that must retire an already-orphaned chain cannot do it quietly either: it warns on
  stderr and writes `orphaned:true` into the permanent evidence trail. The archived pair still
  fails verification on its own, so the evidence is moved, never destroyed.
- In practice this path is nearly unreachable — a truncated IDL is *small*, and only an oversize
  file rotates — but "unreachable" is not a guarantee, so it is made loud rather than assumed away.

Also fixed: a latent prune bug. `<idl>.chain*` matched the body's `<idl>.*` KEEP glob, silently
spending a KEEP slot **and putting the live sidecar on the delete list**. The chain family is now
excluded and pruned separately to equal depth, so every archived body stays paired with the chain
that proves it.

**Tests:** `tests/rotate-idl-chain-epoch.bats` — 16 tests, each guarantee held by its
discriminator pair (the green case *and* the case that must go red), including the rc-7 regression
pin, archive independent-verifiability, archive-tamper-still-caught, and both anti-launder refusals.

### Dogfood trace — an epoch transition over 800 real IDL records

```
run 1 (under threshold)   rotate-autonomy-logs: rotated=0 skipped=1 seal=ok
                          cc-idl verify → OK: 800 sealed line(s) intact          rc 0
run 2 (forced rotation)   rotate-autonomy-logs: rotated=1 skipped=0 seal=ok
  artifacts               idl.jsonl                             ← successor epoch
                          idl.jsonl.chain                       ← fresh genesis chain
                          idl.jsonl.20260726T022853Z            ┐ same stamp:
                          idl.jsonl.chain.20260726T022853Z      ┘ body + its proof
  live verify             OK: 1 sealed line(s) intact                            rc 0
```

The three properties that matter, each read off the trace:

- **Live verify stays green across the rotation** — `rc 0`, where the pre-fix world returned `rc 7`
  forever.
- **The retired epoch still proves itself.** Verifying the archived pair alone:
  `OK: 801 sealed line(s) intact · head ccf45e8b`, `rc 0`. Evidence is retired, not weakened.
- **The epochs are genuinely continuous.** The successor's first record reads
  `"prev_head":"ccf45e8bfe3bb65087df87d5a4c85dcbc3b0381439a1586b7fc45e74f000780c"` — the exact head
  of the archive it replaced, and itself sealed into the new chain.

And the guarantee survives retirement rather than merely relocating: rewriting one record inside the
**archived** body still trips the chain — `TAMPER: chain diverges at line 400 … rc 7`.

### Live state, repaired

The code fix alone would have been inert. On the live box the chain sealed 6,910 links against a
1,734-line IDL, and in that state `cc-idl seal` **silently no-ops** — it reports `sealed 0 new` and
exits 0, because there is no positive tail to seal. So the periodic seal would have run hourly and
done nothing, forever.

`--repair-chain-epoch` was therefore run against live state:

```
repair: retired orphaned chain (6910 links, head 3c1aa303) → idl.jsonl.chain.20260726T013419Z
repair: successor epoch opened and sealed (seal=ok); prior head is recorded in the IDL, not discarded.

$ cc-idl verify
OK: 1760 sealed line(s) intact · 108 unsealed tail line(s)     rc 0
```

The 6,910-link chain is retired to `idl.jsonl.chain.20260726T013419Z.gz` (277 KB, intact), and its
final head is recorded in the IDL as an `idl_epoch_repair` record. **The autonomy substrate has
verifiable tamper-evidence again for the first time since 2026-07-19.**

## 3. The gates were the defect for everything else

For the five episodic tools, "never invoked" is not a wiring defect — it is a *usage* fact about a
tool whose moment has not come. The actual defect was in the **attestation**.

`never-stuck-gate.sh` proves its invariant with `exists_all`: LEG 2 attests each state's guardian
and LEG 3 each failure-class cover **by the existence of a file**. LEG 4 adds deployment (is it
symlinked?). None of these can see whether the thing has ever *run*. So:

> `(b) WAITS are OWNED: disk contracts with deadline+action (cc-wait)` — attested **green**
> because `bin/cc-wait` exists, whether or not a single wait on the box goes through it.

That is a false green, and it is how seven primitives stayed "gate-attested" while dormant.

**Fix (landed):** a new **LEG 4b — exercise (effect-read)** reports each primitive's last real use
from its durable artifact: `USED` / `DORMANT <n>d` / `NEVER`. It is deliberately a **report, never
a bar**, for the reason §1 gives: a true `NEVER` is not automatically a defect, and the one time
this repo graded dormancy as a failure it got `cc-route` wrong. Surface the fact, name the oracle,
leave the judgment to the reader. Live output now reads:

```
LEG 4b — exercise (effect-read; deployed ≠ invoked. READ-ONLY, never a failure):
  · DORMANT    cc-wait → last effect 10d ago
  · NEVER      cc-run → no artifact at ~/.claude/cc-run
  · DORMANT    cc-bind → last effect 11d ago
  · NEVER      cc-respawn → no artifact at ~/.claude/respawn
  · USED       cc-route → last effect 0d ago
  · DORMANT    cc-digest → last effect 6d ago
  · DORMANT    cc-idl → last effect 6d ago
```

The DORMANT-7 finding is now something the gate *says out loud* every run, instead of something an
ad-hoc audit had to rediscover.

## 4. cc-digest — kept, and deliberately not auto-wired

`cc-digest` is the only one of the five with a genuinely missing automatic caller: it is designed
as a **daily batched operator surface**, and no periodic job runs it (2 digests exist, Jul 18-19).

It is **not** superseded by `cc-board` / `cc-blockers`, which was the obvious retire argument. It
carries a section they do not: the **D9 inert-check** — a monitor that flags a hook which abstained
on *all* of its recent evaluations and fired none of them. That is the detector for exactly the
failure class this whole item is an instance of, so retiring it would remove the one automated
guard against the next DORMANT-7.

It is not wired here because a daily launchd job is a **C10 operator hand-step**, outside what this
work may load. Two things are worth knowing before it is activated, both consequences of §2:

- its phone push is inert (no `PUSHOVER` credentials — a separate pending activation), so the
  digest lands on disk only;
- its D9 read looks back over a window of the IDL, which now rotates — a long lookback can cross an
  epoch boundary and silently see less history than it thinks. Worth checking when it is activated.

---

## What landed

| Change | File |
|---|---|
| Rotation-epoch chain + periodic seal + anti-launder repair verb + prune fix | `scripts/rotate-autonomy-logs.sh` |
| 16 discriminator-paired tests | `tests/rotate-idl-chain-epoch.bats` |
| LEG 4b exercise report (deployed ≠ invoked) | `scripts/never-stuck-gate.sh` |
| This decision | `docs/research/dormant-bin-tools-decision-2026-07-26.md` |

**Open (operator, C10):** activate a daily `cc-digest` job if the batched morning surface is wanted.

## Lessons worth carrying

1. **Grep finds call sites; only artifacts find use.** For agent-invoked tooling, absence of a
   caller is the *normal* state. Grade liveness by durable products, and put the oracle outside the
   working tree — `git checkout` rewrites mtimes and will fake freshness.
2. **A detector stuck ON is worse than a detector that is off.** An always-firing alarm reads as
   noise, and it destroys the signal it exists to carry. `cc-idl verify` returning rc 7 forever was
   a bigger problem than the 93%-unsealed figure that got reported.
3. **Existence is not attestation.** A gate that proves a property by `test -f` proves only that
   someone built something. Deployment is a second bar; exercise is a third.
4. **Never auto-heal a state that is indistinguishable from an attack.** Rotation artifacts and
   truncation attacks look identical from inside the tool. The repair is explicit, it refuses the
   ambiguous case, and it records what it retired.
