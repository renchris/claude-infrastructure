# W5-B — the transplant lock gains custody, so a re-limited target can be moved again

**Worktree** `/Users/chrisren/Development/.worktrees/wt-lr-w5b` off `ea5012b30` ·
**commits** `c03309e7b` (lr-transplant + suite), `5976cad79` (lr-ingest-verify C3 + guard suite),
`1b49ae9ce` (the --force/custody fix the mutation pass found) ·
**suites** `tests/lr-transplant.bats 1..19` all ok (was 1..5) ·
`tests/lr-resume-tombstone-guard.bats 1..11` all ok (was 1..9) ·
**mutation 17 built / 17 killed / 0 survived.**

---

## 1. What changed, and why

### 1.1 The state the lock could not express

`lr-transplant.sh`'s lock answered exactly one question — *has THIS move already happened* — and a
second limit asks a different one. A→B lands; B hits its own limit hours later; `--from B --to C`
was refused **twice over**, and the spec named only the first refusal:

| site | tree (pre-change) | what it did with `--from B --to C` |
|---|---|---|
| ONE | `:88-98` | lock's `to` is B, target is C ⇒ `REFUSED — already transplanted to B, not to C` |
| TWO | `:129-132` | `[[ -e "$LOCK" && $FORCE -ne 1 ]]` — **existence, no target comparison at all** ⇒ `REFUSED — lock exists` |

Teaching site ONE to accept a hop and stopping there leaves the hop refused at site TWO. Both now
carry the exemption, and the mutation pass builds one mutant per site (M5, M6) to prove neither is
load-free.

### 1.2 The lock now records CUSTODY

```
{"sid":…,"from":B,"to":C,"ts":<now>,"pid":…,"host":…,
 "owner":C,"ts_first":<the FIRST claim's ts>,"chain":["A","B","C"]}
```

* **`owner`** — who holds the session NOW. `lrt_lock_owner()` reads it with `to` as the fallback,
  and that fallback is not decoration: every lock on disk today was written by the old writer.
  All three decision sites (`lrt_already_done`, refusal site ONE, the hop test) go through that one
  function, so there is a single state model rather than two readers that can drift.
* **`chain`** — every store visited, in order. Read forward on each hop; when the existing lock
  carries none (a pre-W5-B lock) it is reconstructed from that lock's own `from` + `owner`, which
  keeps the origin store in the record.
* **`ts_first`** — the first claim's stamp, carried forward, while **`ts` is REFRESHED**. This is
  the CLAIM-GRACE INVERSION the brief named: `bin/cc-limited:969` treats `NOW - ts <= CLAIM_GRACE_S`
  as "in grace", so carrying the original `ts` forward would render a freshly-claimed second hop as
  an overdue claim the instant it was taken. M10 mutates exactly that and dies.

The write at `:133-135` is a truncating `>`, so there was no read-modify-write path at all; the hop
reads the old record **before** it (`lrt_lock_str`, `lrt_lock_chain`).

**Every minted field has a reader** (the brief's condition for minting one):

| field | read by |
|---|---|
| `owner` | `lrt_lock_owner()` → `lrt_already_done`, refusal site ONE, the hop test (lr-transplant.sh) |
| `chain` | the hop's read-modify-write (lr-transplant.sh); **lr-ingest-verify.sh clause C3** (§1.4) |
| `ts_first` | the hop's read-modify-write, which carries it forward; the stdout receipt |

The receipt (`{"hop":N,"ts_first":…,"chain":[…]}` on stdout) is not decoration either:
`lr-handoff.sh:825` writes this stdout **verbatim** into the bundle's `transplant.json`, which
outlives the lock — locks are transient on this box and tombstones are not
(`lr-lib.sh:528-536`, measured 2026-09-20).

### 1.3 Two seams the hop is unsound without

* **`$FROM` binds with `pwd -P`** (`:30`). See §4's survivor note on M1 for the honest scoring:
  as implemented it is defence-in-depth at the comparison site (both sides go through `lrt_rp`) and
  load-bearing for the value RECORDED — the lock's `from`, hence `chain[0]`, which later readers
  compare by string.
* **the lock dir honours `LR_STATE_DIR`** (`:54`). Every READER already resolved it that way —
  `lr-lib.sh:511`, `lr-fire-resume.sh:244`, `lr-fleet.sh:69`, `bin/cc-limited:88`,
  `hooks/recover-inject.sh:55`. This WRITER was the one place hardcoding `$HOME`, so a fleet run
  with `LR_STATE_DIR` set wrote its locks where nothing looked for them. Unset — production today,
  confirmed by grep over `scripts/ bin/ hooks/ commands/` — the path is byte-identical to before.
  `tests/lr-transplant.bats` now pins `LR_STATE_DIR` in `setup()` at the same path it always used,
  which seals the suite against an ambient value instead of sealing it by accident through `$HOME`.

### 1.4 lr-ingest-verify clause C3 — the coupling the spec missed

`C3` asserted `lock.to == manifest target_cfg` by exact string equality. The moment `to` is
rewritten in place, the FIRST hop's bundle fails C3 **forever** — a bundle that was correct when it
was cut, gating the fast-path ingest. C3 now accepts `to` **or** membership in the recorded chain:

```sh
elif jq -e --arg t "$TCFG_M" '(.chain // []) | (type=="array") and (index($t) != null)' "$LOCK" …
```

`type=="array"` is not ceremony: without it a malformed `"chain":"…"` makes `index` do a *substring*
search and a wrong target can pass. `jq -e` exits non-zero for false **and** for an unparseable
lock; both fall to FAIL, which is the direction C3 already takes on a lock it cannot read
(`predicate-refusal-is-not-a-negative`, stated rather than assumed).

**The FAIL text is unchanged, deliberately**: `tests/lr-ingest-verify.bats:253` pins
`*"FAIL C3 — lock "*"says to="*` and that file is outside my set. Changing the message would have
reddened a sibling's suite. One clause changed; the file was not refactored.

### 1.5 `--force` and custody — the decision the mutation pass forced

The hop test does **not** consult `$FORCE`. Both refusal sites already carry their own
`$FORCE -ne 1`, so a conjunct there gated no override; all it would have decided is whether a
forced move off the store the lock ALREADY names throws that lock's chain away — which costs the
earlier hops' bundles their C3 pass and buys nothing, because nothing the lock says was
contradicted. A forced move off some OTHER store still rebuilds the record, which is right: there
the lock and reality disagree. Both halves are pinned (§4, M4 and M18). I shipped this because the
mutation pass surfaced it, not because the brief asked — see §4's survivor notes for why the
alternative was a test asserting the worse behaviour.

---

## 2. SF-j is REFUTED — verified by executing the path

The spec's acceptance item SF-j says a request replayed through `lr-transplant.sh` under
`env -u CLAUDE_CODE_SESSION_ID` yields `source_retired:0` because "`lr-transplant.sh:97` skips the
rename", and calls it **red today**. It is not red, and `:97` is a bare `fi`.

The guard is at `:162-166` and reads:

```sh
if [[ $KEEP_SOURCE -ne 1 && "${CLAUDE_CODE_SESSION_ID:-}" != "$SID" ]]; then
```

With the variable **unset**, `${CLAUDE_CODE_SESSION_ID:-}` expands to the empty string, which is
**not** the sid, so the condition is TRUE and the rename runs. Executed against the tree
(2026-09-20, before any of my edits, on a scratch fixture):

```
{"ok":true,…,"source_retired":1,…}
/tmp/sfj/from/projects/slug/<sid>.jsonl.handed-off
```

The condition that DOES skip the rename is the opposite one: the **live session driving its own
move** (`CLAUDE_CODE_SESSION_ID == SID`), which is what the comment at `:157-158` says it is for.
Both directions are now pinned by *"the source is retired even with CLAUDE_CODE_SESSION_ID UNSET
— SF-j refuted"*, so the refutation cannot rot, and M13 (inverting `!=` to `=`) kills it five ways.
**No fix was implemented for SF-j; there is no defect there.**

---

## 3. Verified anchors — every one re-read from the tree at `ea5012b30`

`scripts/limit-recover/lr-transplant.sh` (pre-change numbering, as the brief gives them):

| anchor | verified | note |
|---|---|---|
| `:30` | ✓ | `FROM=$(cd … && pwd)` — LOGICAL |
| `:34-37` | ✓ | same-projects-store refusal, above all lock logic |
| `:54` | ✓ | `LOCK_DIR="$HOME/.reso/limit-recover/locks"` hardcoded |
| `:57-82` | ✓ | `lrt_already_done()`; realpaths both sides at `:62-63` |
| `:88-98` | ✓ | refusal site ONE; the message is at `:94` (`:93` is the `if`) |
| `:129-132` | ✓ | refusal site TWO — existence only |
| `:133-135` | ✓ | `NOW` at `:133`, the truncating `printf > "$LOCK"` at `:134-135` |
| `:159-161` | ✓ | tombstone `{handed_off_to,target_transcript,ts,lock}` |
| `:162-166` | ✓ | the `mv "$SRC" "$SRC.handed-off"` guard — intact, and it STAYS |

Other files (read-only for me):

| anchor | verified | note |
|---|---|---|
| `lr-ingest-verify.sh:336` | ✓ | the `[ "$_to" = "$TCFG_M" ]` arm; `_to` read at `:335`, FAIL at `:337` |
| `bin/cc-limited:969` | ✓ | `if NOW - ts <= CLAIM_GRACE_S: continue` |
| `lr-lib.sh:511` | ✓ | the brief's `:505` is the section comment; the `LR_STATE_DIR` default is at `:511` |
| `lr-fire-resume.sh:244` | ✓ | same default |
| `lr-lib.sh:543-562` | ✓ | `lr_transplant_target`; the brief's `538-563` covers its header comment's last lines |
| `tests/lr-ingest-verify.bats:248-254` | ✓ | pins the C3 FAIL substring — the constraint on §1.4 |
| `tests/lr-handoff-launcher-quoting.bats:692` | ✓ | a **stub's** echo of a C3 FAIL line, not the real script — harmless |

**Only `tests/lr-transplant.bats` executes the real script.** The other six suites that mention
`lr-transplant` either stub it (`lr-handoff-close-source.bats:127`,
`lr-handoff-launcher-quoting.bats:409`) or hand-write its artifacts
(`lr-fleet.bats:875`, `handoff-selfclose-transplanted-source.bats:156`,
`handed-off-session-guard.bats:42`, and `lr-resume-tombstone-guard.bats:43` before this change).

---

## 4. Mutation table

Harness `/tmp/w5b-mutate.py` (not committed — it is scaffolding, and it rewrites tracked files).
One mutant per ADDED arm, applied one at a time to a pristine copy, **the whole suite** run against
each, the subject restored and **sha256-verified after every mutant** (the harness asserts it and
prints the final comparison). Final run: `/tmp/w5b-mutation4.log`, baseline
`tests/lr-transplant.bats 1..19 rc=0 fails=0`.

**17 built · 17 killed · 0 survived.**

| # | arm removed / inverted | verdict | first killing case |
|---|---|---|---|
| M1 | `pwd -P` on `$FROM` (`:30`) | KILLED(1) | a hop whose `--from` reaches the owner through a SYMLINK |
| M2 | `LR_STATE_DIR` honoured by the writer | KILLED(1) | the lock is written where every READER looks |
| M3 | the hop is never recognised (`SECOND_HOP=0`) | KILLED(10) | a RE-LIMITED target can be moved ON |
| M4 | every lock is a hop (`SECOND_HOP=1`) | KILLED(5) | a lock naming a DIFFERENT target still refuses |
| M5 | refusal site ONE's hop exemption | KILLED(9) | a RE-LIMITED target can be moved ON |
| M6 | refusal site TWO's hop exemption | KILLED(9) | a RE-LIMITED target can be moved ON |
| M7 | `owner` as the authority (falls back to `to`) | KILLED(1) | OWNER is the authority on custody |
| M8 | carrying `ts_first` forward | KILLED(1) | the hop keeps ts_first and REFRESHES ts |
| M9 | the legacy lock's `ts` as the origin stamp | KILLED(1) | a PRE-W5-B lock still hops |
| M10 | refreshing `ts` (the claim-grace inversion) | KILLED(1) | the hop keeps ts_first and REFRESHES ts |
| M11 | reading the recorded chain forward | KILLED(1) | a THIRD hop keeps the WHOLE chain |
| M12 | reconstructing a chain from a pre-W5-B lock | KILLED(1) | a PRE-W5-B lock still hops |
| M13 | the source-retirement guard's polarity (SF-j) | KILLED(5) | the first run moves it and retires the source |
| M14 | C3's hop-chain acceptance (lr-ingest-verify) | KILLED(1) | C3: the FIRST hop's bundle still verifies |
| M15 | writing `owner` into the lock | KILLED(2) | a RE-LIMITED target can be moved ON |
| M16 | writing `chain` into the lock | KILLED(6) | a RE-LIMITED target can be moved ON |
| M18 | the hop test being INDEPENDENT of `--force` (re-adds the conjunct) | KILLED(1) | `--force` off the store the lock DOES name keeps the chain |

### The two survivors this pass actually had, and what each one bought

Both came from the FIRST clean run (`/tmp/w5b-mutation3.log`), and neither was answered by writing
a test that pins the status quo:

* **M1 survived at first** (`pwd -P` → `pwd`, whole suite green). The brief's reasoning — "your new
  `lock.to == realpath($FROM)` test compares a resolved path against an unresolved one" — is right
  about the SPEC's shape and **not true of the implementation I wrote**: the hop test resolves both
  sides through `lrt_rp`, so the binding at `:30` is defence-in-depth there and the mutant changed
  no comparison. What it DOES change is the value RECORDED: the lock's `from`, and therefore the
  first entry of `chain`, would carry the symlink alias. The chain is compared **by string** — by
  the next hop's reader and by C3 — so an alias in it is a store no later reader can match. The
  symlink case now asserts the recorded `from` is physical, and M1 dies. Had I left it, the whole
  `:30` change could have been reverted with the suite still green.
* **M17 survived** (removing `$FORCE -ne 1` from the hop test). The honest reading is that the
  mutant was **better than the original**: both refusal sites already carry their own
  `$FORCE -ne 1`, so the conjunct gated no override — it only decided whether a forced move off the
  store the lock already names threw that lock's chain away, which costs the earlier bundles their
  C3 pass and buys nothing. **I took the mutant** (`1b49ae9ce`) rather than write the case that
  would have pinned the worse behaviour, and replaced it with M18, which re-ADDS the conjunct and
  dies on the new case. A survivor whose fix is a test asserting the status quo is worth a second
  look; this one turned out to be a design defect the suite had no opinion about.

### Method note, because it nearly cost the whole table

The first pass produced results I later had to **throw away**. Admission (`cc-bats`,
`CC_BATS_MAX_ROOTS=2`) was held by a 3-hour `nice`d trunk job plus five sibling W5 worktrees, so
the harness starved; I stopped it and restarted under cc-bats' own documented waiver — and killing
the **zsh wrapper** left the python child alive and re-parented (`kill-the-leaf-not-the-wrapper`,
in reverse). Two harnesses then mutated and restored the SAME two files concurrently for several
minutes, and the tell was not a crash: it was the final restore check printing `False` for
`lr-ingest-verify.sh` and one mutant's killer list making no sense. Both result sets were
discarded and the pass re-run alone. **Every number in the table above is from
`/tmp/w5b-mutation4.log`, a run whose final restore check prints `True` for both files.** The
generalisable half: a mutation harness must verify its own restore *and* refuse to start beside
another copy of itself — the corruption is silent, and it fabricates both kills and survivals.


---

## 5. Where the spec is wrong

1. **Every `lr-transplant.sh` line anchor in § W5 is stale** (as the brief warned). `:59-69` is
   `lrt_already_done`, not the writer; `:97` is a bare `fi`; `:70-72` (cited by
   `lr-ingest-verify.sh:328`'s comment) is inside `lrt_already_done`.
2. **"the lock gains `owner` (= `to`)" names ONE refusal site.** There are two, and the second
   (`:129-132`) compares no target at all, so the spec's change alone leaves the hop refused.
3. **SF-j's premise is false** — see §2. `source_retired` is `1`, not `0`, under
   `env -u CLAUDE_CODE_SESSION_ID`, and the reason is that an unset variable is not the sid.
4. **The spec never mentions `lr-ingest-verify.sh` C3**, which the in-place rewrite breaks for every
   first-hop bundle. That coupling was found by the recon and is fixed here.
5. **The spec's acceptance puts the two hop cases in `tests/lr-resume-tombstone-guard.bats`.** They
   are there (cases 10, 11) as an *integration* of the writer with that file's reader — after A→B→C
   the guard must refuse the INTERMEDIATE store — but the unit-level hop cases live in
   `tests/lr-transplant.bats`, the only suite that executes the real script.

---

## 6. Residuals — each with the command that re-measures it

**R1 — `lr_transplant_target` cannot follow a ≥2-hop chain once the lock is reaped. MEASURED, not
predicted.** This is the hazard the brief named, and my change is what makes it reachable (before
it, A→B→C was refused). With the lock present the lock path answers correctly, because the hop
rewrites it in place. Once the lock is gone — and `lr-lib.sh:528-536` records that locks are
transient on this box while tombstones are durable — the tombstone fallback (`lr-lib.sh:548-560`)
stops at the first hop: A's tombstone names B, and the successor test
`for pd in "$to"/projects/*/"$sid".jsonl` matches nothing at B, because hop 2 renamed B's copy to
`.jsonl.handed-off`. A husk pane standing at the ORIGIN store of a double hop is therefore
invisible to `lr_husk_state` / `lr-fleet --locate`. Measured:

```
WITH LOCK    A -> [/tmp/res2/C] rc=0
LOCK REAPED  A -> []            rc=1     ← the residual
LOCK REAPED  B -> [/tmp/res2/C] rc=0
A tombstone says: /tmp/res2/B
```

Re-measure (the fixture is rebuilt from scratch; `$W` is this worktree):

```sh
mkdir -p /tmp/res3/state/locks /tmp/res3/{A,B,C}/projects/slug
printf '{"type":"assistant"}\n' > /tmp/res3/A/projects/slug/$S.jsonl
LR_STATE_DIR=/tmp/res3/state bash $W/scripts/limit-recover/lr-transplant.sh --sid $S --from /tmp/res3/A --to /tmp/res3/B
LR_STATE_DIR=/tmp/res3/state bash $W/scripts/limit-recover/lr-transplant.sh --sid $S --from /tmp/res3/B --to /tmp/res3/C
rm -f /tmp/res3/state/locks/$S.lock
LR_STATE_DIR=/tmp/res3/state bash -c '. '$W'/scripts/limit-recover/lr-lib.sh; lr_transplant_target '$S' /tmp/res3/A; echo rc=$?'
```

`lr-lib.sh` is W5-A's file, so I did not take it. Two fix shapes, in preference order: **(a)** make
`lr_transplant_target`'s tombstone leg transitive — if the named store holds `<sid>.jsonl.handed-off`
**and** its own `HANDOFF.json`, follow it; **(b)** have the hop write the `chain` into the tombstone
too and let the reader take its last element. (b) is one line here, but it mints a field with no
reader until (a)'s owner lands it, which is exactly what this brief forbids — so it is offered, not
taken.

**R2 — `lr-ingest-verify.sh:332` still hardcodes `$HOME/.reso/limit-recover/locks` as C3's fallback
lock path**, while the writer now honours `LR_STATE_DIR`. Unreachable today: it is a fallback for a
`transplant.json` with no `.lock` key, and that file IS lr-transplant's stdout verbatim
(`lr-handoff.sh:825`), which always carries one. One line, inside C3's block, deliberately not taken
— my grant on that file is the clause, and line 332 is where a sibling editing C1/C2 would collide.
Re-measure: `grep -n 'LR_STATE_DIR' scripts/limit-recover/lr-ingest-verify.sh` (expect: no match).

**R3 — the chain carries MIXED path spellings.** `--from` values are physical (`pwd -P`, `:30`) and
`--to` values are logical (`pwd`, `:31`), so `chain[0]` — the origin store, only ever a `--from` —
can be spelled differently from the same store appearing later as a `--to`. C3 compares by exact
string against the manifest's `target_cfg`, which is a `--to`-shaped value, so first-hop bundles
match; the origin store is never any bundle's target, so today nothing depends on it. It becomes a
defect the moment a reader asks "was this session ever at X". Re-measure:
`jq -r '.chain[]' <lock>` against `cd <store> && pwd -P` for each. Fix: bind `TO` with `pwd -P` too
(a no-op for the real config dirs, which are not symlinks).

**R4 — the lock format requires COMPACT JSON, and nothing enforces it.** All three sed readers
(`lr-transplant.sh:87`, `lr-lib.sh:514`, `lr-fire-resume.sh:259`) match the literal `"to":"`, so a
pretty-printed lock — `json.dumps`' default `", "` separators — is invisible to every one of them,
and the failure is silent: the hop simply falls through to "lock exists". Found by my own fixture
doing exactly that. Nothing writes the lock that way today; there is no guard that would catch it
if something started. Re-measure:
`python3 -c 'import json;p="<lock>";json.dump(json.load(open(p)),open(p,"w"),indent=2)'` then run a
hop and watch it refuse.

**R5 — the mutation harness is not committed** (`/tmp/w5b-mutate.py`, `/tmp/w5b-mutation4.log`). It
rewrites tracked files in place, which is not a thing to leave in the tree for someone to run by
accident, and its mutant anchors are exact source strings that rot on the first refactor. The table
above is the artifact; the harness is scaffolding. Re-derive by rebuilding it from the table — each
row names the arm precisely enough to re-anchor.

---

## 7. Suites, with their plan lines

Both run under cc-bats' own documented waiver (`CC_BATS_MAX_ROOTS=0` + `CC_BATS_WAIVER_REASON`,
recorded to `~/.claude/state/bats-waivers.jsonl`): admission on this box was held by a 3-hour
`nice`d trunk job (`timeout -k 10 10800 … bats tests/account-cl*.bats`) plus five sibling W5
worktrees, and 30 minutes of 20-second polling never got a slot. Each run is one suite of ~19
sub-second cases, serial.

```
tests/lr-transplant.bats             1..19   19 ok   0 not ok     (was 1..5 at ea5012b30)
tests/lr-resume-tombstone-guard.bats 1..11   11 ok   0 not ok     (was 1..9  at ea5012b30)
```

Gates on every touched file, all clean: `shellcheck -S warning -x` (both `.sh` and both `.bats`),
`bash -n` + `/bin/bash -n` on `lr-transplant.sh` (it is `#!/bin/bash`, i.e. bash 3.2 under launchd),
`scripts/pipefail-sigpipe-lint.sh`, `scripts/bats-assert-liveness.py`.

The plan line is asserted, not assumed: a suite that REFUSES emits no `not ok` and exits 0, so the
harness reads `1..N` out of every run and the counts above are from that line.
