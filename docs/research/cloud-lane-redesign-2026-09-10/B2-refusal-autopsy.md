# B2 — Cloud-lane land-refusal autopsy

Read-only. Stores parsed record-at-a-time; **0 parse failures** across `return.jsonl` (3,035 rows),
`refusal-route.jsonl` (949 rows) and the 75 per-session `*.refusal-route` files (675 rows).
Intermediates: `$S/work-B2/{markers.json,distinct-refusals.json,stale-audit.json,msgs/}`.

---

## Headline (the three findings that change what gets built)

1. **The 1,016 land-refused events are 80 branch-heads asked 12.7× each.** The re-ask loop, not the
   causes, is the volume. `d3e207b61` (2026-08-25) closed it: weekly attempts-per-refused-session
   went **16.1 → 12.8 → 1.7 → 1.00 → 1.00**, while the *fire rate rose* over the same window
   (declarations 20/day → 44-55/day). Denominator-controlled; not a volume artifact.
2. **`arm=stale` is a defect, not a design.** `stale_resolved()` ARM 2 tests **file PRESENCE on
   trunk**, not content landedness, so it fires on every edit-only branch. Measured over all 630
   stale routings: **≥ 358 and ≈ 479 of 630 (57-76%) were declared "already landed" over work that
   was not on trunk at that moment**; ARM 1 (the sound test) holds for **0 of 62** stale sessions.
   Because `stale` returns *before* `classify()`, all 630 bypassed classification entirely.
3. **The residual identity wall is a `strip_trailer_block()` bug, not a VM-side wall.** All 5 live
   cases carry the exact `Co-Authored-By: Claude` / `Claude-Session:` block the stripper exists to
   remove; the stripper refuses because the block is not *exactly* the final paragraph.

Two further live defects, both in `cloud-refusal-route.sh` / `cloud-return.sh`:
**rc 69 (SENSOR FAILED) is latched by the refusal cache**, and
**`routed-originator` is logged on undelivered sends — 273 of 313 rows are `no-such-target`.**

---

## (i) Cause × month over all land-refusal events

### The event population (`~/.claude/autonomy/cloud/return.jsonl`, all 3,035 rows)

| outcome | 2026-08 | 2026-09 | total |
|---|---:|---:|---:|
| land-refused | 981 | 35 | **1016** |
| land-refused-cached | 2 | 69 | 71 |
| land-cut (bound/SIGTERM — non-verdict) | 208 | 1 | 209 |
| land-deferred (budget) | 0 | 271 | 271 |
| land-conflict (merge-tree precheck) | 0 | 3 | 3 |
| nothing-to-land | 0 | 12 | 12 |
| returned (landed OK) | 146 | 35 | 181 |
| abstain / waiting / pass-scope / pass-deadline / dry-run / superseded | 869 | 403 | 1272 |

### Cause × month — **the honest instrument, and its limit**

`land_rc` on a `land-refused` row is **not** a cause before 2026-09-04. `cloud-reconcile.sh:80-92`
states that every lander non-zero was collapsed to 70 until `lander_exit()` (`8ce30f3ac`,
2026-09-04). So the rc series measures *the reporting layer* for August and *the cause* for
September:

| land_rc | 2026-08 | 2026-09 | meaning |
|---|---:|---:|---|
| 70 | 741 | 22 | pre-09-04: **undifferentiated bucket** (any lander non-zero, plus re-author failure) |
| 65 | 237 | 2 | cloud-reconcile preflight refusal (branch absent / retired / cannot make a local head) |
| 5 | 0 | 9 | rebase conflict (only visible after `lander_exit`) |
| 143 | 3 | 0 | SIGTERM cut (mis-filed as a refusal; cured 2026-08-11) |
| 6 | 0 | 1 | gate red |
| 69 | 0 | 1 | SENSOR FAILED — `git ls-remote` unreadable |

**Cause read from the artifact bodies instead** (80 `*.land-refused` markers = the last refusal per
session; the body is the lander's own output, so this is a verdict, not an inference):

| cause (from body verdicts) | markers | Aug | Sep | discriminator matched |
|---|---:|---:|---:|---|
| rebase conflict (ship rail exit 5) | 44 | 19 | 25 | `rebase onto origin/main hit a conflict` |
| preflight: cannot make a local head (rc 65) | 17 | 15 | 2 | `could not bring '<b>' … as a local head` |
| identity wall — could not re-author | 10 | 7 | 3 | `It could not be re-authored: …` |
| gate red (ship rail exit 6) | 7 | 4 | 3 | `ship-land: GATE RED` / `gate: smoke RED` |
| cut / GATE-KILLED | 1 | 1 | 0 | `verdict=killed` |
| sensor failed (rc 69) | 1 | 0 | 1 | `SENSOR FAILED — could not read 'origin'` |

The identity wall splits into **two mechanically different causes**:

| sub-cause | markers | dates | class |
|---|---:|---|---|
| `could not create a temporary file to compose the rewritten messages` | 5 | 08-12 … 08-17T06:19Z | **this box** (reaped TMPDIR) |
| `this repo's OWN commit-msg hook REFUSES the message of <sha> and there is no trailer block to drop` | 5 | 08-18, 09-02, 09-03, 09-05 | **reconciler bug** (see §iv-A) |

### Answer to key question (i): distinctness

| measure | value | source |
|---|---:|---|
| `land-refused` events | 1,016 | `return.jsonl` |
| distinct sessions | **80** | — |
| distinct **(session, branch)** | **80** | every session declares exactly one branch |
| distinct refusal **artifacts** (`at:rc:cksum(body)`) the router observed | **674** | the `key` field across 75 `*.refusal-route` files |
| sessions refused exactly once | 42 of 80 | — |
| worst session | 93 events on one branch | `session_014ww5iHuxrTRtNVRpdD5ozY` |

**≈ 92% of the 1,016 are re-asks of a head already judged** (1,016 events over 80 heads). The 674
distinct *bodies* are larger than 80 because the body embeds the run's timestamps and gate output, so
a re-ask of the same head yields a new cksum — the `key` counts *judgments*, not *subjects*. The
subject count is 80, and `d3e207b61` keys on the subject, which is why it worked.

**Distinct (session, seen_sha) is unavailable for the 1,016** — `seen_sha` was recorded in the
artifact from the start but never written to a `land-refused` ledger row (only `land-refused-cached`
carries it: 71 rows → **25 distinct (id, seen_sha)**, i.e. 25 latched heads, 1 head per session, no
session ever had two distinct heads refused). Named blocker, not a gap in the analysis: markers are
overwritten in place, so earlier bodies are unrecoverable.

---

## (ii) Cure table

Windows are ±7 days around the commit's own `%cI`. `land-refused` count / `all land attempts`
(refused + cut + cached + conflict + returned + nothing-to-land).

| cause | cure commit · date · what it did | 7d before | 7d after | residual today |
|---|---|---:|---:|---|
| **bound-kill filed as a refusal** (rc 124/137/143) | `d079576e0` 2026-08-11 — a cut is a non-verdict: `land_rc=-1`, no artifact, no wake | 3 rc-143 refusals total | **0 after 2026-08-11** | 0. `land-cut` becomes its own outcome (209 rows) and is not a refusal. |
| **identity wall — VM authors as `noreply@anthropic.com`** | `25aa774af` 2026-08-10 — `--reset-author` over the range + `Cloud-session`/`Original-commit`/`Original-branch` trailers | n/a (pre-lane) | — | **51 of 80 markers record a SUCCESSFUL re-author** (5 before the TMPDIR cure, 46 after). 130 commits on trunk carry both trailers. Residual: 5 (§iv-A). |
| **reaped TMPDIR → "could not be re-authored"** | `33cf5df17` 2026-08-17T07:50Z — presence-test the temp root, fall back only when it cannot receive a file | 762 refused / 1043 attempts | 214 / 276 | **0.** Last TMPDIR failure 2026-08-17T06:19Z, 91 min before the cure; 46 successful re-authors after it. |
| **the land's own bound-kill debris blocking every retry** | `cd5d009b5` 2026-08-23T08:53Z | 581 / 698 | 5 / 21 | 0 observed. |
| **the re-ask loop** (a verdict re-earned every 300 s) | `d3e207b61` 2026-08-25T23:10Z — skip when `seen_sha` == the artifact's `seen_sha` | 55 refused over 5 sessions (**ratio 11.0**) | 4 over 3 sessions (**ratio 1.33**) | **0 for the loop.** Weekly ratio: W33 16.1 · W34 12.8 · W35 1.7 · **W36 1.00 · W37 1.00**. Residual is the latch (§iv-D). |
| **machine non-verdicts latching forever** (9 GATE-KILLED, 75 LOCK-STARVED) | `8ce30f3ac` 2026-09-04T13:50Z — `lander_exit()` propagates the rail's code so `cloud-return.sh:797` can exempt 9/75 | 22 / 49 | 13 / 106 | **Partial.** 9/75: 0 observed. **69 is NOT exempted** (§iv-D). Mechanism verified: rc 5/6/69 appear in the ledger only from 2026-09-05. |
| **re-firing what the lane already owes** | `124c4da06` 2026-09-04T13:50Z — `bin/cc-dispatch` cloud-admission gate | 22 / 49 | 13 / 106 | Declarations fall to 5·1·4 per day after 09-04 (from 20-32). |
| **rebase conflict paid for at full lander cost** (rc 5, 4-15 min each) | `7d72371ca` 2026-09-07T05:18Z — `git merge-tree --write-tree` precheck at `cloud-return.sh:648-664`; lane leaves the 12-min sweep arm | 33 / 111 | 2 / 44 | **rc 5: 0 after 2026-09-06.** 3 `land-conflict` rows, all 2026-09-07. `land-deferred` 271 → **0 after 09-07**. Population small — see adversarial pass. |

**Confounder named:** the 2026-09-04 and 2026-09-07 cures sit on a collapsing input — declarations
fall from 31/day (09-04) to 5/1/4 (09-07/09/10). Their before/after *volume* is therefore not
evidence. They are verified on **mechanism** instead: the rc series changes shape exactly at
`lander_exit` (rc 5/6/69 first appear 09-05, having been impossible before), and `land-conflict`
first appears on the merge-tree cure's own day.

---

## (iii) `arm=stale` — definition, population, and verdict

### Definition, read from source

`scripts/cloud-refusal-route.sh:367-403`, called at `:476-481` **before `classify()`** — so a stale
verdict short-circuits the whole classifier and routes nothing.

```
stale_resolved() { # <id> <paths-csv> → 0 the work is on trunk
  ARM 1 — local ref ancestry:
    refs/heads/<branch> exists AND merge-base --is-ancestor refs/heads/<branch> <trunk> ⇒ 0
  ARM 2 — "BY CONTENT, when a path set exists":
    for each declared path p:  [ -n "$(git -C $repo ls-tree $trunk -- $p)" ] || return 1
    return 0
}
```

**ARM 2 tests file PRESENCE, not content.** `git ls-tree <trunk> -- <path>` emits a row iff the path
exists in the trunk tree; it says nothing about whether the branch's *changes* landed. ARM 2 is sound
only for a branch that **ADDs** files — the same shape as the ledger's `LIVE_ADDS` rule — and
vacuous for every edit-only branch, which is nearly all of them. The block's own comment says "BY
CONTENT, never by ancestry"; the implementation is presence. (Corpus rule: *Presence ≠ content* —
a gate discharged on `field != ""`.)

The path set makes it worse. `derive_paths()` (`:340-350`) prefers the declaration's `paths=`, which
`527f016bc` fills **only after a successful land** — so on a *refused* branch it is always empty and
the fallback `cc-cloud fill-paths` derives the branch's own touched paths. ARM 2 then asks "do the
files this branch touched exist on trunk?" — which is true by construction for any edit.

### Population

| store | rows | `stale` |
|---|---:|---:|
| per-session `*.refusal-route` (the dedupe store) | 675 | **630** (93.3%) over **62 of 75** sessions |
| central `refusal-route.jsonl` | 949 | 630 |

Aug 604 · Sep 26. Last stale routing **2026-09-06T12:35Z**. Per-session distribution is heavily
skewed: 39 sessions with 1, one session with 46.

### Did any of them still need routing? — audit

Reproduced both arms against the live repo (`/Users/chrisren/Development/claude-infrastructure`):

| test | result |
|---|---|
| ARM 1 holds today (branch ref is an ancestor of trunk) | **0 / 62** |
| ARM 2 holds today (all declared paths present on trunk) | **56 / 62** |
| ARM 2 true while ARM 1 false | **56 / 62** — ARM 2 is doing 100% of the work |
| remote branch still carries commits not on trunk | 46 / 62 |

Landedness settled by **two independent instruments** — the re-author trailer
(`git log origin/main --grep='Original-branch: <b>'`; 130 positives on trunk, so it can say yes) and
a subject-grep control for work that landed by some other path:

| true state of the work | sessions | stale routings |
|---|---:|---:|
| landed via the re-author path (trailer on trunk) | 23 | 323 |
| landed by another path (every branch subject found on trunk, no trailer) | 9 | 134 |
| **never landed** (no trailer, **no** branch subject on trunk) | **27** | **119** |
| partial (some subjects on trunk) | 3 | 54 |

Then the **temporal** test — was the work on trunk *at the moment stale fired*?

* Of the 23 trailer-landed sessions, **18 had ≥1 stale routing before the work reached trunk**;
  **185 of their 323 rows** predate the land. Example: `session_011idcwNXpC1o56ueWpm5e8D` — 37 of 39
  stale routings fired between 2026-08-12T20:18Z and the land at 2026-08-16T08:24Z.
* Of the 9 landed-by-another-path sessions, 5 (121 rows) had their first stale before the land.

**Verdict — `arm=stale` is a DEFECT.**

> Wrong (work not on trunk at routing time): **≥ 358 of 630 (56.8%)** — 119 never-landed + 54 partial
> + 185 pre-land trailer-landed — and **≈ 479 (76%)** once the landed-by-another-path pre-land rows
> are added (that last group's per-row split was estimated from first-stale vs first-land, not
> counted; the 358 figure is exact).

Worked example, fully reproducible:
`session_014ww5iHuxrTRtNVRpdD5ozY`, branch `claude/fire-20260815T093227Z-79031-1`, 46 stale routings
from 2026-08-15T11:43Z. Logged paths `docs/plans/MASTER_VERIFICATION_INTEGRITY.md,
scripts/git-identity-lint.sh, tests/git-identity-lint.bats` — all three present on trunk ⇒ ARM 2
says STALE. At that time the branch carried **5 commits not on trunk**, **0 re-author trailers**, and
its real refusal was the identity wall. The router printed *"every declared path is content-present
on the trunk, so this work has since landed. Nothing routed."*

**Cost of the defect:** the 630 stale rows are 630 refusals that never reached `classify()`, so no
`vm`, `local-only` or `by-design` decision was ever made on them and no originator was woken. That is
why the whole lane routed 4 messages to a VM in a month.

**The fix is one line of predicate, not a redesign:** ARM 2 must compare content, not presence —
e.g. `git diff --quiet <trunk> <branch-ref> -- <p>` per path (empty diff ⇒ that path's content is on
trunk), or the trailer test the repo already emits (`git log <trunk> --grep='Original-branch: <b>'`),
which is exact and costs one command. Keep ARM 2's presence form **only** for paths the branch ADDs.

---

## (iv) Residual refusal causes, 2026-09-08 … 2026-09-10

New refusals in the window: **exactly one** (`2026-09-09T14:08:50Z`, rc 69). Everything else is the
cache answering (`land-refused-cached`, 30 rows) or pass bookkeeping (`pass-scope`, 30 rows).
`land-deferred` is 0 for the whole window (the lane left the sweep tick on 09-07).

**Two heads are latched right now**, and both are still emitting every ~1.5 h:

| session | rc | verdict | retired? | cached rows | verdict |
|---|---:|---|---|---:|---|
| `session_01DS4fZPoGY3LDFuwJFaeQH9` | 6 | `gate: bats RED: tests/autonomy-sweep.bats (failed twice)` → `smoke RED — 1 of 1 direct suite(s) named a failure (1 mapped to YOUR diff)` | yes (`verdict=conflict`) | 23 | **by design** — a real O(diff) finding about the VM's tree |
| `session_01G8BdNzxaQUQ99BSQByUqna` | 69 | `SENSOR FAILED — could not read 'origin' (git ls-remote). This is 'cannot look', NOT 'nothing to land'` | **NO** | 9 | **defect — fixable, ~3 lines** |

### A. Identity wall — commit-msg refusal · **FIXABLE, ~10 lines, high value**

5 markers, live as recently as 2026-09-05. The reconciler reports *"there is no trailer block to
drop, so what it blocks is in the SUBJECT or BODY the VM wrote … Fix the message at the source and
re-push"* (`cloud-reconcile.sh:618`). **That attribution is wrong in all 5 cases.** I replayed
`strip_trailer_block()`'s predicate (`cloud-reconcile.sh:495-533`) against each named sha:

| sha | `interpret-trailers --parse` count (`nt`) | final-paragraph non-blank lines (`n`) | why it exits 1 |
|---|---:|---:|---|
| `60eaebef7` | 2 | 3 | a `(cherry picked from commit …)` line sits inside the final paragraph |
| `c52af905f` | 2 | 3 | same |
| `4b4e47343` | **0** | 3 | a prose line (`Not run in this container: …`) shares the paragraph, so git parses **no** trailers |
| `d17d97d19` | 0 | 6 | the attribution block is at lines 29-30 of a 38-line message; prose follows it |
| `f80ccd504` | 0 | 6 | attribution at 60-61 of 96; `(cherry picked from …)` + a `RE-LAND.` paragraph follow |

All five carry exactly `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>` +
`Claude-Session: https://claude.ai/code/session_…` — the precise pair `githooks/commit-msg:17`
blocks and the stripper exists to remove. The predicate `if (n != nt) exit 1` requires the AI block
to be *exactly* the final paragraph; a `-x` cherry-pick line, an adjacent prose line, or any prose
appended after the block defeats it.

**Cost:** drop the "final paragraph must equal the parsed trailer set" coupling and delete the
blocked lines wherever they are — i.e. filter the message through the hook's own pattern instead of
positional trailer parsing, or (safer, keeps one arbiter) retry the strip on each paragraph. The
positive control already exists: 46 markers show the re-author succeeding after 2026-08-17.

### B. Rebase conflict (rc 5) · **BY DESIGN — already priced correctly**

44 of 80 markers. A conflict is a fact about branch × trunk that the VM's shallow clone cannot
resolve. `7d72371ca` moved it from a 4-15 min lander run to a ~1 s `merge-tree` precheck that files
no artifact, no wake and no latch, and hands the row to `cloud-retire-terminal.sh` (`verdict=conflict`).
Nothing left to fix — but note the corpus rule that *re-landing the content cannot clear a patch-id
divergence*; the retire pass, not a re-land, is the discharge.

### C. Preflight rc 65 · **BY DESIGN, with a cheap improvement**

17 markers, 14 of one exact shape: `could not bring '<branch>' into … as a local head — local
'<branch>' has diverged, is checked out nowhere, and even a forced re-fetch from 'origin' failed.
This is not the stale-residue case.` A branch deleted from the remote (retired VM, GC'd) is
terminal. Improvement, not a fix: 65 is a *preflight* refusal that files a `land-refused` artifact
and wakes the originator with "LAND REFUSED", which mis-frames "the branch is gone" as "your work
was rejected".

### D. **rc 69 SENSOR FAILED is latched by the refusal cache · DEFECT, ~3 lines, live now**

`cloud-return.sh:620-635` skips a land whenever `seen_sha` matches the artifact's, with **no rc
exemption**. The machine-non-verdict exemption two blocks down is `case "$land_rc" in 9|75)`
(`:797`) — desk-land's two codes only. `cloud-reconcile.sh:74` documents 69 in exactly the terms
that arm exists for: *"A failed `git ls-remote` exits 69 with zero rows emitted, never
0-with-no-candidates. A caller that read a sensor failure as an empty fleet would report the cloud
landing path healthy at exactly the moment it went blind."*

Measured: `session_01G8BdNzxaQUQ99BSQByUqna` refused rc 69 at 2026-09-09T14:08:50Z, and has emitted
`land-refused-cached prior_rc=69` on every pass since — through 2026-09-10T12:56Z. Its artifact says
*"Re-run when the remote is reachable."* The cache says *"not re-asking until it moves."* The
declaration is **not retired**, so this is live debt, and the head can never move (the VM is done).
`66` (NOTHING TO LAND) and `64` (usage) belong in the same exemption by the same argument.

### E. Gate red (rc 6) · **BY DESIGN — this is the one the routing loop was built for**

7 markers. Named suites, read from the bodies: `tests/autonomy-sweep.bats`, `tests/fleet-activate.bats`,
`tests/cc-relogin-poll.bats`, `tests/claude-accounts-*.bats`, `tests/capacity-admit-active.bats`.
Named failures include `not ok 58 M4: the activation is staged in the repo SSOT…`,
`not ok 74 router M7 + S4…`, `not ok 6 a bare run mutates NOTHING…`, and one
`not ok 1 bats-gather-tests` (a **parse failure of the whole file** — per the corpus rule, that is a
syntax break, not a failing test, and it must not be folded into a flake count). These are O(diff),
reproducible verdicts about the VM's own work and are exactly what `arm=vm` should send home.
The routing loop sent **4** in a month, because `stale` ate the queue.

### F. **`routed-originator` is logged on undelivered sends · DEFECT, ~2 lines**

Not a refusal cause, but it is why the repaired arm would still deliver nothing.
`cloud-refusal-route.sh:549-554`:

```
      if [ "$rc" -eq 0 ] || [ "$rc" -eq 3 ]; then
        record_route "$id" "$A_KEY" "$ARM" originator ...     # the DEDUPE store — success only
      else
        say "    (not recorded — the next pass retries the wake)"
      fi
      ledger "$id" "routed-originator" ...                    # the LEDGER — unconditional
```

Of the 313 central `routed-originator` rows: **273 `verdict=unresolvable … reason=no-such-target`,
37 `the declaration names no notify-back target` (rc 3 stand-down), 1 `interrupted`, and
2 `DELIVERED`.** Because the dedupe store is skipped on failure, the same refusal is re-sent every
pass forever: `session_012DTHPWRscJUF986hz1R33Y` — 97 central rows, **0** per-session rows.
273 undelivered over 7 sessions, 2026-08-26 → 2026-09-09. The ledger reads "routed" 313 times for
2 deliveries. (Same family as the corpus's *Claimed vs checked* / *A reader that cannot prove
delivery must not consume*.)

---

## What a repaired arm must still handle

Ordered by residual volume after every cure above:

| # | must handle | why the current arms cannot |
|---|---|---|
| 1 | **Content landedness** | `stale` ARM 2 is presence-only; it pre-empts `classify()` for 93% of routings. Fix before anything else — every other arm is downstream of it. |
| 2 | **A dead notify-back target** | 273 of 313 sends went to `target=5`, a pane that no longer exists. A repaired classifier routes correctly into a hole. Needs a fallback (role `desk`, or the item's backlog row) and a bound on re-send. |
| 3 | **The identity wall's *fixable* half vs its *by-design* half** | `classify()` rule 2 matches any `could not be re-authored` and calls it `by-design` ("the VM has nothing to fix"). For the commit-msg subtype the emitting line says the opposite — *"Fix the message at the source and re-push"* — and rule 2 fires before rule 4, so it can never reach `arm=vm`. Split the arm on `REAUTH_DETAIL`'s subtype. |
| 4 | **Sensor/preflight non-verdicts (69, 66, 64, 65)** | Filed as refusals, latched by the cache, and woken as "LAND REFUSED". Extend the `9\|75` exemption and stop filing an artifact for a preflight. |
| 5 | **Gate reds naming a suite** | The only class the VM can act on, and the class the loop was built for. 7 markers; 4 routed all month. |

---

## Adversarial self-pass (integrated above; here is what it changed)

* **"Your trailer test is one-armed — absence of a trailer proves nothing."** Correct, and it moved
  the number. I added a subject-grep control: **9 of the 39** no-trailer sessions have *every* branch
  subject on trunk (landed via a non-reconciler path) and **27** have *none*. The wrong-stale figure
  fell from a naive 307 to an exact **358 on a different, larger basis** (once the pre-land timing
  test was added to the trailer-landed group). The instrument can say yes (130 positives on trunk)
  and can say no.
* **"The seen_sha before/after is confounded by the fire rate collapsing."** Refuted for that cure:
  declarations *peaked* at 44-55/day exactly when refusals collapsed (08-25 → 08-29). Held for the
  09-04 / 09-07 cures, where the fire rate genuinely collapsed — so those are validated on mechanism
  (rc propagation, first `land-conflict` row) and explicitly **not** on volume.
* **"Show a post-cure event that would have re-triggered each 'cured' cause."**
  · *TMPDIR* — 46 markers after 2026-08-17T07:50Z record `re-authored N commit(s) as
  <ren.chris@outlook.com>` succeeding, against 5 before; the last TMPDIR failure is 91 min before the
  cure. Strong.
  · *seen_sha loop* — W36 and W37 both read **exactly 1.00** attempts per refused session over 32 and
  2 sessions. Strong.
  · *bound-kill filed as refusal* — 209 `land-cut` rows exist as a separate outcome; 0 rc-143
  refusals after 2026-08-11. Strong.
  · *merge-tree precheck* — **population too small to tell.** 3 `land-conflict` rows, all on the
  cure's own day, and 0 rc-5 refusals after 2026-09-06 — but only 5-6 lands ran per day in that
  window, so "0 after" is consistent with "no branch was asked". Verified on mechanism only.
  · *`lander_exit` propagation* — verified on mechanism (rc 5/6/69 are *impossible* before it and
  present after), not on volume.
* **"Are you sure `stale` isn't right for branches that ADD files?"** It is right for exactly that
  case, and the fix must preserve it — stated in §iii.
* **"Is the router even still alive?"** `refusal-route.jsonl` last written 2026-09-09T09:17Z; last
  stale routing 2026-09-06T12:35Z. Alive, low volume.

---

## Blockers / uncertainties (named, not hedged)

1. **Per-event cause for the 1,016 is unrecoverable.** `<id>.land-refused` is overwritten in place,
   so only the *last* body per session survives (80 bodies). The 674 routed `key`s give a per-artifact
   rc and timestamp but no body. Every cause count in this report is over the 80 markers; the rc
   series is over the 674. Neither is a per-event cause census, and one cannot be built from disk.
2. **rc 70 is not a cause before 2026-09-04** — it is a collapse bucket by the reconciler's own
   documentation. Any cause attribution for August rests on body text, not on rc.
3. **The 'landed by another path' pre-land row split (121 rows, 5 sessions) is estimated**, not
   counted — from first-stale vs first-trunk-land, not per row. The exact wrong-stale floor is 358;
   479 is the estimate.
4. **`git cherry` / patch-id was deliberately not used** to decide landedness (the re-author rewrites
   every commit, so patch-ids differ by construction and `cherry +` proves nothing here). The trailer
   + subject pair is the substitute, and both arms are stated.
5. **Not measured:** whether the `pass-scope` cursor (132 rows) or `land-deferred` (271 rows, all
   Sept, 0 after 09-07) ever starved a specific branch out of the rotation. Out of scope for a
   refusal autopsy; it is a scheduling question, and `land-deferred` reaching 0 suggests it is closed.

## Alternatives considered and ruled out

| approach | ruled out because |
|---|---|
| Decide the cause from `land_rc` alone | `cloud-reconcile.sh:80-92` — collapsed to 70 until 2026-09-04. Would have reported "the cause is unknown-70" for 75% of the population. |
| Decide landedness with `git merge-base --is-ancestor <pushed-sha> <trunk>` | The land re-authors; the pushed sha never becomes an ancestor. This is the §1 rule the whole subsystem is organised around, and it is why ARM 1 exists. |
| Decide landedness with `git cherry` | Patch-id differs after re-author/rebase; the repo's own memory records `cherry +` as not-absence. |
| Take `arm=stale` at face value ("the work landed, nothing to route") | Falsified: ARM 1 holds for 0 of 62; 27 of the 62 branches have no commit subject on trunk at all. |
| Treat `routed-originator: 313` as 313 deliveries | Falsified from the rows' own `send` field: 273 `no-such-target`, 2 delivered. |
| Run `cloud-refusal-route.sh --sweep` / `--chain` to reproduce a routing | Out of bounds — `--sweep` sends. All arms were reproduced read-only from source + git. |
