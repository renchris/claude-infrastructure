# T9 — Silent failures in land -> converge -> live (ADVERSARIAL)
Status: IN PROGRESS. Written incrementally.
Repo read-only. Every claim tagged RAN (I executed it) or READ (I read source only).

## Live state at time of investigation (RAN, 2026-09-17)
Shared checkout `~/Development/claude-infrastructure` (= `LIVE_REPO`, wrap-ledger.sh:1086):
- `git rev-parse HEAD` = `145c32f53`; `git rev-parse origin/main` = `29a4918c3`
- `git rev-list --count HEAD..origin/main` = **3** (behind)
- `git rev-list --count origin/main..HEAD` = **1** (AHEAD — `145c32f53 docs(research): union-alpha drain routing`)
- `git cherry origin/main HEAD` => `+ 145c32f53...` (not present on trunk by content either)

=> the live checkout is **DIVERGED**. `git merge --ff-only` — the only advance mechanism
(deploy-live.sh:52) — is structurally impossible until that commit lands or is dropped.
This is the "shared-checkout commit is a fleet converge block" class, live right now.

## F1 — deploy-live's budget arm exits BEFORE its divergence arm (VERIFIED, conviction 95%)
RAN: `bash scripts/deploy-live.sh --dry-run --offline` =>
> `deploy-live: waiting — no GREEN stamp among the newest 200 commits of origin/main (... at depth 945 (24c598bac1c7) ...); lag 3 commit(s) / 0h14m, inside the degrade budget (25 / 6h) — no advance, and none is due yet.`

READ: the divergence detection lives at deploy-live.sh:2360-2404 (`DIV_CLASS=diverged-unlanded`,
:2403) and the hard `die` at :2543. The within-budget wait exits at **deploy-live.sh:2318**, i.e.
**42-225 lines earlier in the flow**. So while lag is inside the budget, the sanctioned operator
diagnostic prints a sentence that reads *healthy* ("no advance, and none is due yet") over a
checkout that could not advance if one were due.

- Operator SEES: "inside the degrade budget — none is due yet."
- Operator WRONGLY CONCLUDES: converge is fine, just early.
- Bound on the silence: the budget window (25 commits / 6h). After that the `die` at :2543 fires
  loudly. So this is a **deferred**, not permanent, alarm — but it is silent for up to 6h, and a
  6h window is more than enough for a session to close ✅ over it.
- NOT verified: whether the loud arm actually fires after budget expiry on THIS tree (would require
  waiting 6h or mutating the budget env var, which the repo's own settings DENY for a real run).

## F2 — wrap-ledger never measures the live layer unless the rung is already ✅-eligible (VERIFIED, conviction 97%)
RAN: `bash scripts/wrap-ledger.sh --machine` =>
`RUNG=🔧 ... LIVE=0 LIVE_SRC=skip LIVE_LAG=0 LIVE_ADDS=0 LIVE_DIVERGED=0 LIVE_BREACH_WHY=`

READ: `compute_live_layer` has exactly ONE call site, wrap-ledger.sh:1827, inside the `else`
branch reached only after DIRTY/AHEAD/custody arms have all passed (:1800-1826). The header at
:1806-1810 states the design intent: *"ONLY here do the custody count, the operator-step count and
the live-layer read matter — on the 🔧/📦 paths none can change the answer, so none is ever paid
for"*.

That reasoning is sound **about the rung** (🔧 outranks 🚀 in the priority order) and false about
the FIELDS. The emitted values `LIVE_LAG=0 LIVE_ADDS=0 LIVE_DIVERGED=0` are byte-identical to a
measured-healthy live layer. `LIVE_SRC=skip` is the only discriminator, and it is one field among
60. This is the **fail-safe-default-mimics-the-healthy-state** class, and it is in the repo's own
memory index (`fail-safe-default-mimics-the-healthy-state.md`).

THE COMPOUNDING PART, and why this is worse than a cost optimisation: the shared checkout's tree is
dirty essentially always (26 changes right now, several untracked files dated 2026-08-09/08-11), so
the ✅-eligible path is rarely reached THERE — and the shared checkout is the only place a
divergence can occur. **The one instrument carrying a `LIVE_DIVERGED` arm is dark exactly where the
fault it detects lives.**

Self-corroborating evidence from the repo: wrap-ledger.sh:1743-1746 records that a `command not
found` bug in `stale_clause` shipped and was NOT caught by a live run, *"this session's tree was
dirty, so compute_live_layer() was never called"*, concluding *"A path the ✅-gate skips is a path
your smoke test skips too."* They wrote the lesson and left the blindness.

---

# THE HEADLINE (verified, conviction 97%)

**The land→converge→live chain's alarms are not silent. Its ALARM CHANNEL is.**
Every page the chain writes lands in `~/.claude/autonomy/pages/`. That store is drained by
`autonomy-sweep.sh`, which notifies `role:desk`. `~/.claude/cc-roles/desk` contains `672`
(written 2026-09-09 17:03). **Pane 672 is not live** — `it2 session list --json` returns 11 panes
(13,3,17,19,20,24,25,28,6,5,16) and 672 is not among them.

MEASURED over the live IDL (`~/.claude/autonomy/idl.jsonl` + 8 rotated `.gz` archives):

| date | sweep `fired` rows delivered=True | delivered=False | median `new_pages` |
|---|---|---|---|
| 2026-09-07 | **13** | 0 | 2 |
| 2026-09-08 … 09-15 | *(no `fired` rows at all)* | — | — |
| 2026-09-16 | 0 | **31** | 231 |
| 2026-09-17 | 0 | **61** | 250 |

Last 24h: **66 of 66** `fired` rows carry
`{"delivered": false, "channel": "none"|"notification-center-advisory", "notify_rc": 0,
"why": "nothing proved a reader — records left unseen, the next sweep re-surfaces them"}`.

Note `notify_rc: 0` beside `delivered: false` — the notifier SUCCEEDS at delivering nothing. The
sweep is honest about it (it refuses to mark the records seen), which is the right polarity; the
honesty is written to a log with no reader.

Two distinct outages stacked, and the second was created by the fix for the first:
1. **2026-09-08 → 09-15:** the sweep self-bound at 400 s never reached §3 (summary+notify) at all.
   `autonomy-sweep.sh:459-470` records this: *"across 49 self-bound rows, `stopped_before` is
   `1-collect-pages-alarms` 35 times and `0b-author-death-join` 14 times — the two EARLIEST
   checkpoints, and nothing else, ever"*, and §3's *"last `fired` row is 2026-09-07T21:14:23Z."*
   RAN, today: that starvation is now largely cured — over the last 24 h there is exactly **ONE**
   self-bound row and it stopped at `2b-ii-grouping-sweep` (checkpoint ~7), elapsed 403 s/bound 400 s.
   So the source comment's own measurement (dated 2026-09-16) was stale within one day.
2. **2026-09-16 → now:** the sweep reaches §3 again and fires — into a dead pane.

Accumulated while nobody could be told: **271 `.page` + 1,116 announce-alarms + 149 completion-push
+ 23 dead-letters**, and `operator-readout.sh --render` renders that as ONE line:

```
 ◆ 1554 escalation record(s) unseen — cc-escalations ack --all
```

Today's `deploy-diverged-unlanded.page` — *"the live layer is FROZEN … every landed hook, script and
belt above the live tip is inert for as long as this holds"* — is **1 of 1,554**, i.e. 0.06% of that
counter.

## F3 — the harm chain closes: the offered remedy silences the signal (VERIFIED, conviction 90%)
The one action the readout offers for the counter is `cc-escalations ack --all`
(`bin/cc-escalations:59`, `:222-225` — `is_seen … || mark_seen`). `mark_seen` writes two PATH-derived
markers (`bin/cc-escalations:39-48`: the sha256 of the path, and `<basename>.seen`). Both readers —
`hooks/escalation-watch.sh:143` (`my $key = substr(sha256_hex($path), 0, 32)`) and
`hooks/operator-readout.sh:448-449` — key on the **path**, never on content.

Deploy pages split into two keying schemes, and the split is the defect:

| shape | example | count now | behaviour |
|---|---|---|---|
| **sha-keyed** | `deploy-degraded-<sha>.page`, `deploy-host-red-<sha>.page` | **59 of 66** | a NEW path per event ⇒ always resurfaces, and accumulates forever |
| **class-keyed** | `deploy-diverged-unlanded.page`, `deploy-dirty-tree.page`, `deploy-copy-drift.page`, `deploy-refusal-escalation-<class>.page` | **7 of 66** | ONE stable path, content overwritten in place |

So: the 59 low-value sha-keyed pages generate the noise that makes `ack --all` the rational move,
and `ack --all` writes a seen-marker for the 7 class-keyed pages — which are the ones carrying
"the live layer is FROZEN". Markers are aged out at `CC_SWEEP_SEEN_TTL_DAYS` default **7**
(`autonomy-sweep.sh:73`, deleted by `find … -mtime +$SEEN_TTL -delete` at `:1144`) and are never
refreshed, so **an ack silences the ENTIRE divergence class for 7 days** — including a different
divergence, on different commits, next week. The file is rewritten with fresh content and a fresh
`date +%s` on line 1, and no reader looks at either.

- NOT verified: I did not execute `ack --all` (it writes). The mechanism is read from source on
  both the writer and both readers; conviction 90% rather than 97% for that reason.

## F4 — a read-only `--dry-run` MINTS an operator page (VERIFIED by source, conviction 92%)
`deploy-live.sh:2406-2413`: `refusal_bump` is correctly gated
(`:786 [ "$DRY_RUN" -eq 0 ] || return 0`, with the header at `:783-785` stating the intent —
*"An operator running this by hand, or any --dry-run/--offline decision-only call, must not move a
counter that pages"*). The **page write immediately below it is gated on nothing**:
```
  refusal_bump "$DIV_CLASS" "$DIV_MSG"
  mkdir -p "$PAGES_DIR" 2>/dev/null || true
  { date +%s ; ... } > "$PAGES_DIR/deploy-$DIV_CLASS.page"
  die "$DIV_MSG"
fi
if [ "$DRY_RUN" -eq 1 ]; then ...          # <-- the dry-run check is 3 lines BELOW, at :2416
```
Consequence: the page's own timestamp stops meaning *"the unattended lane observed this at T"*. Any
agent or operator running the sanctioned read-only diagnostic re-stamps it. Today's page reads
`1789621434` (00:03) and I cannot tell whether a launchd tick or a sibling session's probe wrote it.
- NOT verified by execution: my own `--dry-run --offline` exited at the budget arm (`:2318`) and
  never reached `:2406`, so I did not observe the write. Read from source only.

## F5 — the within-budget wait is invisible in the lane's own log (VERIFIED, conviction 93%)
`deploy-live.sh:395`: `asay() { [ "$AUTO" -eq 1 ] || printf 'deploy-live: %s\n' "$1"; }` — under
`--auto` (the launchd lane) **asay prints nothing**. The within-budget wait at `:2318` is an `asay`.
RAN: `grep -c 'deploy-live: waiting' ~/.claude/autonomy/postland/deploy.log` = **0** across 6,171
lines carrying **103** `deployed` advances and **11** `ESCALATED` rows. So a converge that is quietly
not advancing leaves zero trace in the deploy log; only advances and escalations do.
Combined with F1 (the budget arm exits above the divergence arm) and F2 (`LIVE_SRC=skip` on a dirty
tree), a **diverged checkout inside the lag budget produces no signal on ANY of the three surfaces.**

## F6 — `--offline` lag is a LOWER BOUND, correctly documented, still consumed as a reading (VERIFIED, conviction 88%)
`deploy-live.sh:1916-1930`: `--offline` asserts an already-fetched `origin/main` exists and
**never fetches** (`:1930` vs the `else` branch's `g fetch origin main` at `:1932`). The contract is
deliberate and its reasons are good (a Stop hook must not do a network round-trip; a failed fetch
would make the renderer report a blocker it caused itself — `:1907-1911`).
The residual: the lag it prints can only UNDERSTATE, i.e. it fails toward *"inside the budget,
nothing to do."* `wrap-ledger.sh:1427-1431` states the same property for its own read.
RAN today: `.git/FETCH_HEAD` was 0 minutes old, so today's `lag 3` was accurate — this one did NOT
fire today. The repo's own memory records a measured instance: `--dry-run --offline` reported
`lag 20/25, inside budget` five minutes before a fetch showed `27/25, breached`.
- Polarity note: this is the RIGHT failure direction for an actuator (never advance on stale data)
  and the WRONG one for a DIAGNOSTIC, and the same code path serves both.

## F7 — the live-layer auditor only runs after a successful advance (VERIFIED, conviction 94%)
`scripts/host-suites.manifest:1-8` partitions the corpus: `postland-verify.sh` runs
`tests/*.bats` MINUS the manifest (the TREE verdict); `deploy-live.sh` runs exactly the manifest
(the LIVE verdict). The live call site is `deploy-live.sh:2665` — `host_checks "$TARGET"` — the LAST
statement in the file, after the merge. `deploy.log:6057` records a real instance of the skip:
*"DID NOT RUN, because this exit: the post-advance migrations_converge and host_checks."*
So **while the converge is blocked, the suite that would assert the live layer is exactly the suite
that does not run.** A new form of the "deployed layer bootstrap circle" the manifest header names.

`~/.claude/autonomy/postland/host-green` currently reads:
```
tests/deploy-parity-live.bats 1789619784 fad2bcc1f75bc47364c3e2aea571e0590ba7b461
tests/test-walltime-lint.bats 1789620703 fad2bcc1f75bc47364c3e2aea571e0590ba7b461
```
i.e. green at `fad2bcc1f`, the last advance. The checkout has since moved to `145c32f53` and
`deploy-parity-assert.sh` now exits **1** against it. The green row is stale-but-present.

## F8 — `--falsify-host` reads the suite NAME and ignores the epoch and the sha (VERIFIED, conviction 96%)
`deploy-live.sh:357-362`:
```
  if [ -f "$HOST_GREEN" ]; then
    while IFS= read -r _fh_row || [ -n "${_fh_row:-}" ]; do
      case "${_fh_row%% *}" in "$_fh_suite") exit 0 ;; esac
    done < "$HOST_GREEN"
  fi
```
The row format is declared at `:303` as `"<suite> <epoch> <sha>"`. **Neither the epoch nor the sha is
ever read by any consumer** (`grep -n HOST_GREEN deploy-live.sh` returns 12 sites; the only reads are
this one and the merge/rebuild block at `:1143-1157`).
`exit 0` on this falsifier is contractually *"the premise is GONE — refuse the claim"*
(`bin/cc-premise run_falsifier`). So a green recorded at ANY sha at ANY time in the past permanently
retracts every future `post-deploy HOST RED` item for that suite — on evidence about a tree that may
be arbitrarily old. The file's own header (`:299-302`) reasons *"Only an explicit green row is
load-bearing, which keeps this probe's single success state single"* — true, and it never asks
WHICH TREE the green was about.
Live exposure: because F7 means no host check runs while the converge is blocked, the row is neither
refreshed nor deleted; it just keeps answering "cured" for as long as the freeze lasts.

## F9 — a fail-safe default that mimics health, in the one field an operator would read
Already stated as F2. Restating the shape because it recurs: `LIVE_LAG=0 LIVE_ADDS=0 LIVE_DIVERGED=0
LIVE_BREACH_WHY=` are the emitted values when NOTHING WAS MEASURED, and they are byte-identical to
the values of a perfectly converged live layer. The single discriminator is `LIVE_SRC=skip`.
`wrap-ledger.sh:1151` acknowledges it in a comment: *"0 alongside LIVE_SRC=skip/n-a/unknown means
'not counted', which those already say."* Consumers do check `LIVE_SRC`
(`completion-assert.sh:683`, `operator-readout.sh:828`), so the in-repo consumers are safe; a HUMAN
or a future agent reading the 60-line `--machine` dump is not.

## Candidates I checked and did NOT confirm (stated so the null is on the record)
- **Converge advances FILES but creates no symlink for a newly added file.** The MECHANISM is live
  and named by the auditor's own output (`deploy-parity-assert`: *"A raw ff/pull moved the shared
  checkout. It advances FILES but creates NO symlinks"*), and `hooks/validate-bash.sh:1352` denies a
  bare `git merge --ff-only` in the shared checkout for exactly this reason. But RAN today:
  parity-assert reports **0 missing across all 22 classes**, and
  `git diff --diff-filter=A --name-only <last-advance>..origin/main` adds only
  `docs/research/union-alpha-drain-2026-09-17/*` — which is not a deployed class, so `LIVE_ADDS`
  correctly scores it 0. **Not firing today**; the exposure is real the moment a pending commit adds
  a file under `bin/cc-*`, `hooks/`, `scripts/` etc.
- **TAP filtered through `grep '^not ok'` reading as a pass.** Searched `~/.claude/logs/*.log` for
  `nothing ran, nothing was verified` / `DEFERRAL, not a test result`: the only hits are the
  *documentation* of the rule in `validate-bash-unclear.log:83626-83627`, not fresh occurrences.
  **Not confirmed today.**
- **Damping store overwritten in place understating volume.** `deploy-live.sh:403-421` (`damp_ok`,
  `DAMP_FILE` = one file holding `<ts>\n<key>`) and `REFUSALS_FILE` (one line,
  `"<class> <n> <first> <last-esc>"`) are both single-record, overwrite-in-place stores — the shape
  the repo's own `damping-store-understates-emission-volume.md` describes. RAN: both files are
  **absent** right now, so I could not measure an understatement. The `refusal_bump` counter is also
  `--auto`-only and `damp_clear` deletes both on any healthy outcome, so the streak count resets on
  an alternating healthy/blocked pattern. **Mechanism present, harm not measured.**
- **Stale resident-daemon bytes after a converge.** `deploy.log` carries **5** instances of
  `residency: N of M executing resident daemon(s) are running STALE bytes … install.sh reloads a
  resident daemon only on an advance, and only with CC_INSTALL_RESIDENT_RELOAD=1`. RAN today: the
  dry-run reports *"2 of 2 … running current bytes · 1 exempt"*. **Real mechanism, clean today.**

---

# What the operator SEES vs what is TRUE, right now

| Surface | What it says | What is true |
|---|---|---|
| `wrap-ledger.sh --machine` | `LIVE_SRC=skip LIVE_LAG=0 LIVE_ADDS=0 LIVE_DIVERGED=0` | never measured; the layer is diverged and frozen |
| `deploy-live --dry-run --offline` | "lag 3 / 0h14m, **inside the degrade budget** — no advance, and none is due yet" | an advance is impossible at any lag: `--ff-only` cannot run |
| `deploy.log` (103 advances, 11 escalations, 6171 lines) | nothing since the last advance | the freeze began ~28 min after it |
| `operator-readout --render` | `◆ 1554 escalation record(s) unseen — cc-escalations ack --all` | one of those 1554 says the live layer is frozen |
| `host-green` | `tests/deploy-parity-live.bats … fad2bcc1f` (green) | green about a tree the checkout has left |
| `deploy-parity-assert` | `DRIFT` / `UNGATED` / `UNVERIFIED`, **exit 1** | correct — and it is the ONLY surface that is |

The wrong conclusion each invites, in one sentence: *"the converge lane is idle because there is
nothing to do."* The true statement: *"the converge lane is frozen, and every landed hook, script
and belt above `145c32f53` is inert until someone lands or drops one commit."*

Historical dose, from `~/.claude/autonomy/pages/deploy-refusal-escalation-checkout-diverged.page`
(2026-09-14): *"this refusal has REPEATED 6 times … culprit: checkout-diverged … **last sanctioned
advance: 36h ago** … the live checkout carries **8 commit(s)**."* So the observed cost of one
un-noticed divergence on this box is **36 hours of a frozen live layer**.

---

# Cheapest alarm per confirmed failure, with POLARITY

Polarity rule applied throughout: count NOT-success, and make the alarm's firing rate a property of
the FAULT, not of the traffic.

| # | Failure | Cheapest alarm | Polarity check |
|---|---|---|---|
| **A1** | desk role points at a dead pane; nothing has been delivered since 2026-09-07 | In `autonomy-sweep.sh` §3, after the `delivered:false` row is written, compare the row's `ts` against the newest `delivered:true` ts in the IDL. Emit ONE line — `sweep: role:desk has not proved a reader in <N>h (target=<pane>, live=<y/n>)` — **only when N crosses 6h, and again only on each doubling.** | Fires 0× on a healthy fleet (13/13 true on 09-07). Fires once per outage, not 66×/day. Denominator is *consecutive undelivered*, i.e. NOT-success. |
| **A2** | role file is a bare pane id with no liveness binding | `cc-notify --role` already resolves at send time; make it exit non-zero (not 0) when the resolved target is not live, and have the sweep record `channel:"dead-target"` instead of `"none"`. | A `notify_rc: 0` that delivered nothing is the single fact that made A1 invisible. One rc change turns a silent success into a countable failure. |
| **A3** | class-keyed page + path-keyed seen marker ⇒ an ack silences the class for 7d | Key the seen-marker on `sha256(path + content)` for `*.page` only (alarms/completion records are already one-file-per-event). | Strictly monotone in evidence: a page whose CONTENT changed is a NEW event and resurfaces; an unchanged page stays acked. Adds no firing on a quiet box. |
| **A4** | sha-keyed deploy pages accumulate forever (59 now) and drive `ack --all` | Cap each sha-keyed class at its newest N (e.g. 3) at write time; the older ones are already superseded by definition. | Reduces the denominator that destroys A3's signal. Nothing new fires. |
| **A5** | `deploy-live` budget arm exits above the divergence arm | Hoist the ancestry/divergence test (`:2393`) ABOVE the tier ladder. It is 2 `git merge-base --is-ancestor` calls, no network, no write. | A divergence is a *state*, not a *clock*, so it should never be reported through a budget. Fires only when `--ff-only` genuinely cannot run — 0× on a healthy checkout. |
| **A6** | `wrap-ledger` never reads the live layer unless already ✅-eligible | Add ONE cheap arm on the 🔧/📦 paths: `git -C $LIVE_REPO rev-list --count origin/main..HEAD` (~20 ms, no network). If > 0, append `· live layer DIVERGED (N)` to whatever readout the rung already prints. Do not change the rung. | Costs one `rev-list` per close. Fires only on divergence, which is rare and always actionable. Does not add a rung, so it cannot become an unclearable ✅-blocker. |
| **A7** | `asay` silent under `--auto`, so a non-advancing tick logs nothing | Log one line per tick to `deploy.log` at ADVANCE-or-not: `deploy-live: tick verdict=<advanced\|waiting\|blocked:<class>> lag=<n>/<hm>`. | Deliberately fires every tick — but into a LOG, not a page. That makes "the lane has said `waiting` for 200 consecutive ticks" a grep, which it currently is not (`waiting: 0` of 6171 lines). Absence currently means both "healthy" and "frozen". |
| **A8** | `--falsify-host` ignores the sha it was handed | `case "${_fh_row%% *}" in "$_fh_suite") …` → also require the row's 3rd field to be an ancestor of the CURRENT live HEAD, else fall through to exit 1. One `git merge-base --is-ancestor`. | Strictly weakens the ONLY success state, i.e. it can only ever *keep* a claim open. A falsifier that can only retract on fresh evidence cannot mint a false all-clear. |
| **A9** | `LIVE_*` zeros indistinguishable from measured-zero | Emit `LIVE_LAG=- LIVE_ADDS=- LIVE_DIVERGED=-` (not `0`) whenever `LIVE_SRC` ∈ {skip,n-a,unknown}. The `?` convention already exists in this file for unreadable sensors. | Zero new firing. Removes a value that reads as healthy and replaces it with one that reads as absent — the distinction `wrap-ledger.sh:1136` already makes for `?`. |

**The one I would build first is A2**, because it is three lines and it converts the entire class
into a countable failure. A1 then becomes a query over data that already exists.

---

# Ranked by expected harm before anyone notices

1. **Dead alarm channel (F3/A1/A2) — HIGHEST.** Conviction 97%. It is not one silent failure, it is
   the thing that makes every other one silent. Measured dose: **10 days** with zero proved
   deliveries (last `delivered:true` 2026-09-07), 1,554 records queued, and the only offered action
   is a mass-ack that (F3) silences the highest-value class for 7 more days. Every finding below is
   only harmful *because* of this one.
2. **Converge freeze reported as "inside budget" (F1+F2+F5+F7) — HIGH.** Conviction 93%. Measured
   dose on this box: **36 h frozen** on 2026-09-14 with 8 divergent commits. During a freeze every
   landed fix is inert, which is the failure mode this whole repo's `🚀` rung exists to name, and
   three of the four surfaces that should say so say nothing. **Live right now.**
3. **`--falsify-host` retracts host-RED findings on stale evidence (F8) — MEDIUM-HIGH.**
   Conviction 96% on the mechanism, unquantified on incidence. It is a *self-retracting* work item:
   a finding about the live layer closes itself on a green from a tree that no longer exists. That
   is worse than not filing, because the closure looks like a cure. Compounds with F7 (the row is
   frozen in place for the duration of the freeze).
4. **Newly-added-file-without-symlink — MEDIUM, dormant.** Conviction 85% on the mechanism, 0% that
   it is firing today (parity-assert: 0 missing/22 classes). Its harm when it fires is total silence
   — consumer guards are `[ -f x ] && . x`, so the feature is a no-op, not an error — but the repo
   has three independent auditors for it and a `validate-bash` deny on the raw ff. This one is
   genuinely well covered.
5. **`--dry-run` minting a page (F4) — LOW harm, HIGH corrosion.** Conviction 92%. It costs nothing
   directly; it destroys the evidentiary value of every page timestamp, which is the field you would
   reach for when trying to reconstruct how long a freeze lasted.
6. **`--offline` lower-bound lag (F6) — LOW today.** Conviction 88% on the mechanism, verified NOT
   firing today (FETCH_HEAD 0 min old). Correct polarity for the actuator, wrong for the renderer.

---

# Method notes, including my own error
- **RAN vs READ** is tagged per finding above. Everything in the tables under "live state",
  "delivery history", "page counts", and both `deploy-parity-assert` runs is RAN. F4, F8 and the
  `install.sh`-symlink mechanism are READ-only.
- **I made the pipeline-rc error myself, in this investigation.** My first
  `deploy-parity-assert.sh 2>&1 | tail -40` printed `RC=0`; that was `tail`'s status. Re-run with
  the output redirected to a file, the true rc is **1**. This is the same class as the report's
  own "gate refusal filtered into an empty result" candidate — worth recording because it means the
  class is reachable by a careful reader in a single command, not just by a sloppy one.
- **I did not execute** anything that writes: no `ack`, no real `deploy-live` tick, no fetch, no
  commit. The repo was treated as read-only throughout.
- **One claim in the repo's own source went stale within a day** and I corrected it by measurement
  rather than quoting it: `autonomy-sweep.sh:523-527` (dated 2026-09-16) says the sweep stops at
  checkpoint 1 or 2 "with exactly one row anywhere else, ever." Over the last 24 h that is no longer
  true — 1 self-bound row, at checkpoint 7. Cite the file for the mechanism; re-measure the numbers.

STATUS: COMPLETE.
