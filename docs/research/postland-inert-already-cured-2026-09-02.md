# `postland-verify is INERT` was the wrong fault name, and the fix landed a week ago

**2026-09-02.** Backlog `01ab05685857` — *"postland-verify is INERT — newest GREEN stamp 46h old
(max 24h), so nothing is re-proving trunk; this is how 3 red suites went unnoticed"* — was
dispatched to a `--venue cloud` session. **Its cure landed on trunk on 2026-08-25 and the row is
still open.** This is a §14 verdict artifact: the row is closable on `2f165d9b`, and this file is the
path that closes it.

The row is not merely cured. Its *title is the defect* — the sentence was transcribed verbatim out of
a `ship-land.sh` warning that named the wrong fault, and the commit that fixed that warning cites
this row by id as its measured cost.

## 1 · The row is CURED — `2f165d9b`, and it is an ancestor of `origin/main`

    fix(ship-land): a fresh RED stamp is liveness, so "INERT" named the wrong fault
    2f165d9b196e30a4045b963c4aad3c825a72f480   2026-08-25 00:35:01 +0000

`git merge-base --is-ancestor 2f165d9b origin/main` → **0**.

`scripts/ship-land.sh`'s `postland_net_live` computed `inert` from the **newest GREEN stamp alone**,
so one state served two populations whose remedies are opposites:

| population | what the stamps dir does | the real remedy | what v1 printed |
|---|---|---|---|
| the job has **stopped** | nothing stamps at all | `launchctl` | "looks INERT … check that com.claude.postland-verify is loaded" |
| the job **runs** and trunk is **red** | advances every sweep; every verdict non-green | the failing suite(s) | *the same line* — advice that is a no-op precisely when the stamps dir **is** advancing |

`2f165d9b` reads a **second clock** in the same pass over the stamps — newest green is the
CERTIFICATION clock, newest stamp of *any* verdict is the LIVENESS clock — and splits the state four
ways. `tests/ship-land.bats` splits the old single `net INVERSION` fixture into two tests so no one
fixture can pass on both populations again; that test's own comment had encoded the same error
(`red ≠ liveness`) and is corrected.

### Why this row's own title is the proof

The title asserts *"nothing is re-proving trunk"* and its next clause names **three red suites the
net had just stamped**. A stamp written now is the strongest liveness evidence there is; what a red
stamp withholds is CERTIFICATION, not liveness. The two clauses contradict each other, and the
dispatch the row bought went to launchd while nothing went to the suites.

`scripts/ship-land.sh` already carried the law it broke, 600 lines above at the `red` attestation:
one value serving both *"answered no"* and *"could not ask"* fabricated 80 of 156 findings
(memory: `sensor-default-off-makes-blindness-the-shipping-path`).

## 2 · Verification actually run, on `origin/main`, not recalled

`git rev-list --count HEAD..origin/main` → **0**, and `git diff origin/main -- scripts/ship-land.sh
tests/ship-land.bats` is empty: the copy exercised below is trunk's, byte for byte.

`tests/ship-land.bats` cannot run in this venue — its fixtures age stamps with `date -v -48H`, a
BSD-only flag. So `postland_net_live` was extracted from trunk's `ship-land.sh` and **driven
directly** against all four populations, which is the same shape the fix commit's own verification
used. Harness: `stat -f %m` shimmed to its BSD meaning (see §4), stamps aged with real mtimes.

    green fresh                  -> net:live          silent                     ok
    green cold + red FRESH       -> net:uncertified   "NOT CERTIFYING"           ok
                                                       says cc-blockers          ok
                                                       never says launchctl      ok
                                                       never says "looks INERT"  ok
    green cold + nothing fresh   -> net:inert         "launchctl list"           ok
    no green ever                -> net:none          silent (bootstrap)         ok
    POSTLAND_STALENESS_GUARD=off -> net:none          silent                     ok
    ---- 7 passed, 0 failed

**RED-proved.** The identical harness against `git show 2f165d9b^:scripts/ship-land.sh` fails
exactly the alive-but-red arm and nothing else — **4 passed, 3 failed**:

    FAIL green cold + red fresh: NET_STATE=inert want=uncertified
    FAIL alive-but-red still says INERT
    FAIL no cc-blockers

That third line is this row's title being generated. A harness that could not fire has controlled
nothing, so the pre-fix run is the part that makes the post-fix run mean something.

## 3 · The residual is real, and it is NOT this row — trunk is `uncertified`, not `inert`

The fix commit settled which population the live box was in **by trunk rather than by its stamps**,
and that reasoning still holds today, one week later:

    bash scripts/typed-send-lint.sh   ->  rc 1
      TYPED-SEND scripts/handoff-fire.sh:5633  (session-send)

`tests/typed-send-lint.bats` test 17 (*"GREEN on the REAL tree"*) asserts that lint prints `clean`
over the real `scripts/ hooks/ bin/`. That wrapper is **not** in `scripts/host-suites.manifest`, so
it rides the tree corpus of **every** sweep, and its failure is a grep over the tree — deterministic,
not load-dependent, so it survives the retry ladder into a RED stamp every time. A box in that state
stamps continuously and never goes green: newest-green cold, stamps dir advancing. That is
`uncertified` under the landed predicate, and `cc-blockers` is the row that names it.

Two notes for whoever picks that up, neither of them acted on here:

- The **site count moved** since `2f165d9b` was written. It named `handoff-fire.sh:2183` and `:5415`;
  `0e156995` and `9df04881` have since reworked that region and the lint now flags a single site,
  `handoff-fire.sh:5633`.
- That site **does read its send back** — `composer_content` is compared against `/exit` before the
  CR is sent (`scripts/handoff-fire.sh:5633-5636`). So the open question there is whether the lint
  should recognise an inline read-back, or whether the site takes a reviewed
  `typed-send-lint:allow` marker — a judgement about that lint's contract, whose header says
  *"Do NOT add to the allowlist."* Not a mechanical fix, and not this row.

**Why it was not driven here.** Follow-On Gate F2/F3: `handoff-fire.sh`'s pane-send path cannot be
exercised in this venue at all (it needs iTerm2 + `osascript` on macOS), so any change would ship
unverified into the live fire path. Named, not silently swallowed, and not attempted.

## 4 · Honest limits of this verdict

- **Venue.** Linux cloud VM. The live box's actual stamps dir, its `launchctl` state, and
  `~/.claude/autonomy/backlog.jsonl` are all unreachable from here. This artifact settles the row's
  **premise** against trunk; it does not read the operator's box.
- **A container-only red, excluded deliberately.** `scripts/unattended-path-lint.sh` also exits 1
  here, and it is **not** a trunk red: every finding is a macOS binary (`osascript`, `vm_stat`,
  `plutil`, `afplay`, `say`, `gtimeout`, `zsh`) reported unreachable because it does not exist in
  this container, plus rows whose `.plist` could not be parsed. It is the platform analogue of the
  stale-tree trap in backlog `6110fc45141e` — a red that reproduces faithfully in a foreign tree and
  means nothing about trunk. Seven other deterministic tree lints run rc 0 here.
- **`stat -f %m` is BSD-only, and the fallback in `postland_net_live` does not degrade cleanly on
  GNU coreutils.** `stat -f %m "$p" || stat -c %Y "$p"` assumes the BSD form fails silently; GNU
  `stat` instead treats `%m` as a *file operand*, prints a filesystem dump to **stdout**, and exits
  1 — so `$m` becomes that dump concatenated with the epoch, and the next `[[ "$m" -gt … ]]`
  arithmetic aborts the shell under `set -u` (`File: unbound variable`). Recorded, **not fixed**:
  `ship-land.sh` runs only on the operator's macOS box by design (`scripts/cloud-reconcile.sh`'s
  header states a cloud VM cannot run the project-local `/ship`), so this is latent, not live, and
  fixing it is outside this row's frozen scope. The harness in §2 shims `stat` rather than touching
  the script.

## 5 · Disposition

`01ab05685857` is **DONE on `2f165d9b`**. The remedy it asked for — check that
`com.claude.postland-verify` is loaded — was the wrong remedy for the fault the box actually had,
and the message that recommended it has been fixed and pinned by two tests that cannot both pass on
one fixture.

The verification latency the row was reaching for is real and unresolved, but it belongs to
`scripts/typed-send-lint.sh`'s red (§3), which `2f165d9b` recorded as *"Filed separately; it is not
this diff."* Re-dispatching **this** row cannot reach it.
