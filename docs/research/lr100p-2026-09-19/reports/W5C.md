# W5-C — cc-husk-sweep learns that a transplanted session is not a husk to resume

**Commits** (branch `main` in `/Users/chrisren/Development/.worktrees/wt-lr-w5c`, off `ea5012b30`)

| sha | subject |
|---|---|
| `69da2e15d` | feat(cc-husk-sweep): a transplanted session is not a husk to resume |
| `b23b6fdd5` | test(cc-husk-sweep): pin the transplant gate at its lr-lib boundary, and re-anchor the citations |
| `913821f60` | test(cc-husk-sweep): a target cfg with a trailing slash must still name its account |

**Files** — `bin/cc-husk-sweep` (235 → 338 lines) · `tests/cc-husk-sweep.bats` (8 → 19 tests). Nothing
outside the set was touched.

---

## What changed, and why

A limit transplant keeps the **same sid** and moves the session to another account's store, leaving
the source pane at a bare shell — a husk by every test `cc-husk-sweep` applies. It would resolve
that pane, name the **source** account, and under `--resume` type that account's launcher line while
the work is live in another store: two writers, one transcript. The tool had no transplant guard on
any of its three resolution arms and did not source `lr-lib.sh` at all.

Five things were added, each with its own mutant below.

1. **The gate.** After `resolve()` names an account and before the row is built, the sid is asked of
   `lr_transplant_target` against the store it was found in. A hit becomes the verdict
   `TRANSPLANTED→<account>`, and the `--resume` plan loop skips such a row **including under
   `--all`** (`--all` means "the DONE ones too", never "the ones that moved").
2. **`store_for_launcher`** — the cfg-directory derivation the spec could not express (below).
3. **`same_store`** — the `~/.claude ↔ ~/.claude-next` mirror fold, keyed on `projects`.
4. **`acct_for_dir`** — the `next|next2|next3|next4` rendering, matching `lr-fleet.sh:261`.
5. **The lr-lib source ladder** — readlink-first, `bin/cc-find:60-69`'s shape, with a **FATAL** miss.

**The row shape is unchanged** — nine tab fields, nine JSON keys, nine awk columns. The new
classification rides in the existing `verdict` field, so the eight pre-existing tests that pin
`"verdict":` / `"source":` / `"launcher":` over that arity all still pass untouched.

**TRANSPLANTED is on its own channel, not a `resolve()` rc.** The `|| { rows=…unresolved… }` arm
collapses every resolve failure into one literal row and already throws `R_SRC=live-elsewhere` away;
expressing a transplant there would erase both the sid and the target.

### Fail-open vs fatal — the one line of argument

**FATAL** (exit 2, this file's own spelling for an absent hard dependency, matching its `jq` check;
3 is already the typed-yes abort). This guard's only job is to **prevent** an action, so a silently
unreachable library restores the pre-guard behaviour exactly — it types a transplanted session's
resume line into its dead source pane, and nothing says so. `cc-find:68-69` exits for the same
reason. The poller (`lr-reset-poller.sh:1083`) and `lr-fleet.sh:38` guard with `command -v … ||`
because their lr-lib use is **additive**: degrading it loses information rather than taking an action.

Verified in the deployed shape, with a positive and a negative control:

```
$ ln -s <worktree>/bin/cc-husk-sweep $D/cc-husk-sweep
$ env HOME=$H CLAUDE_CONFIG_DIR=$H/nope $D/cc-husk-sweep --pane 99999999
cc-husk-sweep: no husk panes …                                    # readlink rung resolved it
$ cp bin/cc-husk-sweep $D/copied                                  # same file, no symlink to follow
$ env HOME=$H CLAUDE_CONFIG_DIR=$H/nope $D/copied --pane 99999999
cc-husk-sweep: FATAL — lr-lib.sh (lr_transplant_target) not found beside …   (rc 2)
```

---

## Where the spec is wrong — the tree is the fact

**1. The spec names the weaker predicate, and the tree agrees with the brief, not the spec.**
`lr_transplanted_to` is lock-only. `lr-lib.sh:527-542` records that on this box the lock store held
**one** lock fleet-wide belonging to an unrelated sid, while the three panes the predicate exists to
find each carried a transplant tombstone and no lock. I use `lr_transplant_target` (lock **or**
tombstone-naming-a-different-store). This is not a stylistic preference: mutant **M12** swaps in the
spec's predicate and **four cases die** — the tombstone arm is the one that fires in practice.

**2. The spec's call is not expressible, exactly as the brief says.** Both functions take
`$2 = this cfg`, a config **directory**, and `resolve()` never produces one. The registry arm has an
account **label**, the scrollback arm a launcher **name**, the transcript arm a store path.
`store_for_launcher` reads `launcher_for_dir` **backwards** over `STORES` so the two spellings can
never drift; the transcript arm skips the derivation and uses the store it read off disk. All three
arms are separately mutated (M7/M8/M9) and separately tested (cases 9, 11, 12).

**3. Every line anchor in the brief was re-verified. Six are off; one names a line that does not
exist.**

| brief | tree |
|---|---|
| `lr-lib.sh:504-515` `lr_transplanted_to` | signature at **`:510`** (header comment `505-509`) |
| `lr-lib.sh:537-556` `lr_transplant_target` | signature at **`:543`** |
| `lr-lib.sh:517-536` the lock-transience measurement | **`:527-542`** |
| `bin/cc-find:59-69` the ladder | **`:60-69`** (`_CF_SELF` at `:60`) |
| "lr-fleet (`:1011`) guards with `command -v … \|\|`" | **no such line** — the file is 1083 lines; its lr-lib guard is `:38`, a second at `:479` |
| `bin/cc-husk-sweep:99` resolve() | function header at `:97`; `:99` is the field-init line it means |

Correct as written, re-read and confirmed: `cc-husk-sweep:41` STORES · `:90-95` `live_sids`/`is_live_sid`
· `:121`,`:136` the two `is_live_sid` applications · `:122` `R_SRC=live-elsewhere` · `:146-152`
`transcript_for` · `:196` the `unresolved` collapse · `:205`,`:208` the nine-field JSON builder and
the nine-column awk · `lr-fleet.sh:261` the `TRANSPLANTED→` rendering · `lf_acct_of_cfg` at
`:103-107` · `lr-reset-poller.sh:1083` · `tests/cc-husk-sweep.bats:9` exporting HOME.

My own additions cite `bin/cc-find:60-69` and `lr-lib.sh:527-542`, and deliberately **name** rather
than number the two anchors this very patch moved (memory: *insertions break line citations*).

**4. `lf_acct_of_cfg` is not reusable and `lib/account-map.generated.sh` is the wrong dependency.**
The generated map hardcodes `$HOME/.claude-*`, so it cannot see `CC_HUSK_STORES` — the seam every
test in this suite resolves stores through. `acct_for_dir` is a local table over the same basenames
as `launcher_for_dir`: one table, two renderings.

---

## Hazards — how each was actually handled

- **The naive red-proof that passes for the wrong reason.** Every transplant case exports an
  **empty** `CC_HUSK_LIVE_SIDS`, so `is_live_sid` can suppress nothing and the only thing between
  the sweep and a resume is the new code. Proven by running the six new positive cases against the
  **pre-change** binary: `1..16`, cases 9, 10, 11, 12, 15, 16 RED (output captured in the commit
  sequence — cases 13 and 14 are negative controls and passed pre-change by construction, which is
  why they are scored by mutation instead, per *green in both arms is an equivalence guard*).
- **The mirror is not folded.** `same_store` compares `pwd -P` of `projects/`, not of the cfg root —
  the identity `lr_config_dirs` (`lr-lib.sh:26-49`) keys its own dedupe on. Case 13 builds
  `$T/.claude-next/projects → $T/.claude/projects` and asserts the tombstone across that pair is
  **not** a transplant; mutants M3 and M13 both die on it.
- **Source-order divergence.** `STORES` puts `.claude` last, `lr_config_dirs` puts it first, so
  `store_for_launcher claude` matches `~/.claude-next` here and `~/.claude` there. Harmless and
  documented in the function: those are one store, every glob reads the same population, and
  `same_store` folds the comparison. No other agreement between the two orders is assumed.
- **Row arity pinned by 8 tests.** Unchanged — see above.
- **The lossy resolve rc.** Own channel — see above.
- **The two suites pinning the prescription text.** `tests/lead-crash-pane-verdict.bats` `1..15` and
  `tests/lead-crash-surface.bats` `1..18`, both 0 failures. The `--pane 330` / `--resume --pane 330`
  spellings are untouched.
- **`LR_STATE_DIR`.** Pinned explicitly to `$T/lrstate` in every transplant case (`xplant_seals`), so
  the lock store is sealed on purpose rather than incidentally by the tmp `HOME`.

---

## Mutation table

Harness: `w5c_mutate.sh` — apply one mutant, run the suite, `git checkout --`, **verify sha256
against the pre-mutation baseline** (a mismatch aborts the pass). Every run must print a `1..N` plan
line; a `cc-bats` refusal emits no `not ok` and exits 0, so it is recorded `NO-VERDICT` and retried,
never scored. Baseline sha `8ba05ae7570ab83138e2edf599fd973e69d07b653e74cb27dadee6b9bd799fbd`,
restored and re-verified after all 18.

**16 mutants of the added arms: 15 killed, 1 survived.** Plus a 2-mutant compound pair run to make
the one survivor's equivalence claim checkable (M17 killed, M18 the control).

| # | mutation of an arm I added | result | killed by (test #) |
|---|---|---|---|
| M1 | the FATAL on an unreachable lr-lib deleted (fail-open) | **KILLED** | 16 |
| M2 | `store_for_launcher` ignores the launcher, returns the first store | **KILLED** | 9, 10, 11, 14, 15 |
| M3 | the `same_store` fold removed from `transplant_target_of` | **KILLED** | 13 |
| M4 | the `TRANSPLANTED` verdict override removed | **KILLED** | 9, 10, 11, 12, 15, 17 |
| M5 | the `--resume` plan's `TRANSPLANTED*) continue` removed | **KILLED** | 10 |
| M6 | `acct_for_dir` collapsed to one account | **KILLED** | 9, 11, 12, 15 |
| M7 | `R_STORE` not set on the **registry** arm | **KILLED** | 9, 10, 15, 17 |
| M8 | `R_STORE` not set on the **scrollback** arm | **KILLED** | 11 |
| M9 | `R_STORE` not set on the **transcript** arm | **KILLED** | 12 |
| M10 | `CC_HUSK_LR_LIB` stops sealing — falls through to the ladder | **KILLED** | 16, 17 |
| M11 | the empty-target defence `[ -n "$to" ] \|\| return 1` removed | **SURVIVED** | — see below |
| M12 | the spec's weaker predicate `lr_transplanted_to` (lock only) | **KILLED** | 9, 10, 11, 12, 17 |
| M13 | `same_store` compares the cfg **roots** — the naive fold | **KILLED** | 13 |
| M14 | the gate never runs (`[ -z "$R_STORE" ]` inverted) | **KILLED** | 9, 10, 11, 12, 15, 17 |
| M15 | `same_store`'s unresolvable-dir fallback collapses onto `""` | **KILLED** | 17 |
| M16 | `acct_for_dir` drops the trailing-slash strip | **KILLED** | 19 |
| M17 | *compound:* M11 **+** the consumer keys on `transplant_target_of`'s **rc** | **KILLED** | 18 |
| M18 | *control:* the rc-based consumer **alone**, M11's guard intact | SURVIVED (by design) | — |

**Three of these were survivors first, and each bought a test rather than an excuse.**

- **M15** survived the first pass. The fallback keeps two *unresolvable* cfg dirs distinct; collapsed
  onto `""` they compare equal, `same_store` returns true, and **every transplant on the box is
  silently folded away**. Case 17 drives it through the `CC_HUSK_LR_LIB` seam with a stub library
  returning a nonexistent target against a store with no `projects/`.
- **M16** survived the second pass. `lr_transplant_target` prints the target exactly as the lock or
  tombstone recorded it, trailing slash included; unstripped, `${1##*/}` is `""` and the row renders
  `TRANSPLANTED→next` — a confident wrong account, not an error. Case 19 pins it.
- **M11 is a genuine equivalence guard, and the claim is checkable rather than asserted.** Under the
  current consumer — which tests the **string** `$xplant`, not the rc — removing the line changes
  nothing observable: `transplant_target_of` then returns rc 0 with empty stdout, and
  `[ -z "$xplant" ]` suppresses the override anyway. **The mutation it dies on** is the pair
  `{remove the line, make the consumer key on the rc}` = **M17, killed by case 18**, while the
  rc-based consumer **with** the line intact (**M18**) is clean. So the line is exactly what makes an
  rc-based consumer safe to adopt later; it is kept, and its status is measured, not guessed.

---

## Suites run

| suite | plan line | failures |
|---|---|---|
| `tests/cc-husk-sweep.bats` | `1..19` | 0 |
| `tests/lead-crash-pane-verdict.bats` | `1..15` | 0 |
| `tests/lead-crash-surface.bats` | `1..18` | 0 |

Pre-change red-proof of the same suite: `1..16` with 9, 10, 11, 12, 15, 16 RED.

Gates, all green on the final tree: `shellcheck -S warning -x bin/cc-husk-sweep tests/cc-husk-sweep.bats`
· `bash -n` and `/bin/bash -n bin/cc-husk-sweep` · `scripts/pipefail-sigpipe-lint.sh` ·
`scripts/bats-assert-liveness.py`.

---

## Residuals

**R1 — the guard's reach is the arms that name the SOURCE store, by construction.** When a transplant
retires the source to `<sid>.jsonl.handed-off`, the transcript arm's cwd-scoped search finds only the
**target's** copy, so `here` *is* the target, no tombstone there names a different store, and the row
resolves normally with the target's launcher. That is the correct action — it is where the tombstone
would have redirected us — but it means such a row is not labelled `TRANSPLANTED`. The registry and
scrollback arms, which carry the source account, are the ones that needed the guard and have it.
Re-measure how often the source copy is still present:

```bash
for f in ~/.claude*/projects/*/*.HANDOFF.json; do [ -f "$f" ] || continue
  s=$(basename "$f" .HANDOFF.json); [ -f "${f%/*}/$s.jsonl" ] && echo "SOURCE-PRESENT $f"; done | wc -l
```

**R2 — `transcript_for()` returns the FIRST `<sid>.jsonl` across stores, not the source's.** On a
transplanted sid both stores hold that name, so the `CLOSE` column can be read off the *successor's*
copy: case 9's row shows `close:"-"` for a source transcript that says `Good to close: no`. Pre-existing
(`:146-152`), outside my file set, and it only colours a row now classified `TRANSPLANTED` anyway.
Re-measure: `bin/cc-husk-sweep --json | jq -r 'select(.verdict|startswith("TRANSPLANTED"))'`.

**R3 — the scrollback arm is only reachable with `CC_HUSK_PANES_JSON` unset**, so case 11 supplies
its own `it2` fake that answers `session list --json`. That fake is test-local; no new seam was added
to the tool for it.

**R4 — the session scratchpad root is SHARED with the concurrent siblings, and one of them overwrote
my mutation table mid-pass** (`…/d90959db-…/scratchpad/mutants.py`, 2026-09-20 23:01; it came back
holding 35 five-tuples naming `scripts/lib/cc-tui.sh` and `bin/it2-kitty`). It surfaced as a Python
unpack error rather than a wrong mutation only because the tuple arity differed. Everything of mine
now lives in `…/scratchpad/w5c/` with `w5c_`-prefixed names. Worth telling the other waves.
Re-measure: `ls -la /private/tmp/claude-501/*/*/scratchpad`.

**R5 — 8 of the 18 mutant runs needed `CC_BATS_MAX_ROOTS=0` with a recorded `CC_BATS_WAIVER_REASON`.**
Load was 33.79 on 10 cores with five sibling waves running suites, so `cc-bats` refused 12 consecutive
attempts over 5 minutes for M10 and M11 in the first pass. A refusal is not a result, so waiving was
the only way to get a score at all; the reasons are on disk.
Re-measure: `tail ~/.claude/state/bats-waivers.jsonl`.
