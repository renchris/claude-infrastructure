# CRITIC — what is MISSING from SYNTHESIS.md

Completeness critic, wave 2, 2026-09-19. Read-only. Every item = **what · where · the one-line fix**.
Receipts are commands run by this unit (§ R at the end) or a file:line in the wave-2 corpus.
Ranked by what it costs if it ships unclosed.

---

## 1. The flagship acceptance row is built on a registry row that the plan's OWN receipt says does not exist

**What.** § 5's fixture claims *"verbatim copies … of … registry rows `111.json` …, `121.json` …, `147.json`
(sid `07e30aeb`, `claude-tertiary`, pid 84167, live — the P8/Db 21:14Z state)"*, and the expected screen's first
row is `RECOVERABLE (stub)  #147  07e30aeb`. § 10's own registry enumeration, eleven pages later, reads
**"NO row for 147, 09e64dcb, 98f02458, 4bc1159f, 07e30aeb"**. Both cannot be true, and the live store agrees with
§ 10: `ls ~/.claude/cc-registry/` ⇒ 38 rows, no `147.json`; `grep -l 07e30aeb ~/.claude/cc-registry/*.json` ⇒ rc 1.
The `#147` provenance is P6 R8, which ran `kitten @ ls --match id:147` and annotated it *"147 = registry row for the
limited session 07e30aeb"* — that is a **kitty window id**, asserted as a registry row and never joined.
**This is not a fixture-cosmetics problem.** W2a's own state table makes `RECOVERABLE` require `blocked ∧ live ∧
IN-PLACE ∧ procs == 1`, and *live* comes from step 2 (`cc-registry ∩ ps`). With no registry row and no `--resume`
leaf, `07e30aeb` resolves to **NO-PANE** — the row that tells the poller to *spawn at reset*. So the plan's
headline correctness win over the prototype ("it DROPPED a live, limit-blocked, pane-held session", § 1 / P8 R3)
is a state the plan's own predicate cannot reach, and § 5's closing instruction — *"the LIVE run … must render the
same five sids in states consistent with the live registry at that instant"* — is unsatisfiable as written.

**Fix.** Before W2b is briefed, re-derive `07e30aeb`'s true state from the live stores and either (a) rewrite drill
row 1 as `NO-PANE` and demote `#147` to a `--kitty` title-only column, or (b) add the second liveness source item 2
names and keep `RECOVERABLE` — but never ship a fixture that asserts a row the plan's § 10 receipt denies.

---

## 2. Liveness is SINGLE-SOURCED on a store whose completeness the plan's own unit REFUTED, and the DROP row that waves it away is false

**What.** P5's verdict is **"COMPLETE is REFUTED"** — 3 of 14 of today's `rate_limit` sids have no registry row
(21.4 %), 14 of 44 sessions today have none. § 7 DROPPED disposes of the second index with: *"the `KITTY_WINDOW_ID`
fallback in `session-register.sh:127` closes the measured no-row class at 1 line."* **P5 R5 measures two causes and
the fallback closes neither of the dominant one.** Cause 1 is *"Keyed by pane, one row per pane … A pane that runs
session A then B keeps only B"* — structural overwrite, nothing to do with the address; that is what left
`98f02458` (3.0 MB, `entrypoint: cli`, last record IS the cap), `28f07827` and `e442434c` rowless, all three with
panes already registered at their cwd. Cause 2 (no address) is *"the 2 `sdk-cli` rows … by design"*, and those
carry no `KITTY_WINDOW_ID` either. So W1's +1 line closes **0 of the 3** measured rate_limit no-row sids, and the
fix is prospective in any case — it cannot give a row to a session already running, i.e. to every session alive
during the mass cap the tool exists to answer.
Consequence, stated in the plan's own vocabulary: a live limited pane whose sid was overwritten by a pane recycle
renders **NO-PANE**, the poller parks it, and R2 spawns a second session beside the live one.

**Fix.** Give the census a second liveness source that survives pane reuse — `ps -eo pid=,lstart=,command=` is
already being forked once, so join the sid out of the live `claude` argv/cwd for sids the registry cannot see — and
rewrite the § 7 DROPPED justification to the measured one (pane-overwrite, not address).

---

## 3. `parked/` is an enumerated source whose record shape cannot feed step 1's own classification formula

**What.** W2a step 1 enumerates `stop-failure/*__*.jsonl` ∪ `parked/*.json`, then says *"group by sid; MAX(**ts**)
row wins … acct_death = name[basename(**config_dir**)] … kind/cap = `lr_predicate.classify_text`(**last_assistant_message**)
∘ **error** field"*. A parked record is `{"sid","acct","cfg","cwd","kind":"weekly","reset_at_utc","parked_at"}`
(measured: `cat ~/.reso/limit-recover/parked/*.json`, 8 files live right now). It has **no `ts`, no `config_dir`,
no `last_assistant_message`, no `error`** — four of the five fields the formula names — and its `kind` is the
poller's third vocabulary (`session|weekly|fable`), which judge-Db-latency already flagged. A sid known only from
`parked/` (marker GC'd, or a tick that parked before the marker aged) therefore enumerates with **no cap, no
resets_at, no account key** and falls through the state table to whatever the empty classification yields. No
row in § 4 or § 5 exercises a parked-only sid, and § 10 confirms *"`parked/` 8 files (none of the drill sids)"* —
so the branch ships untested by construction.

**Fix.** Add a parked-record adapter in step 1 (`ts←parked_at`, `config_dir←cfg`, `cap←{session→five_hour,
weekly→seven_day, fable→model_scoped:Fable}`, `resets_at←reset_at_utc`) and one W2b row over a parked-only sid.

---

## 4. The mirror double-count is specified at the wrong depth — the symlink is one level below the root the plan dedupes

**What.** Step 0 says *"roots = `readlink -f` dedupe (`.claude-next → .claude`)"*. `~/.claude-next` is **not** a
symlink: `ls -ld ~/.claude-next/projects` ⇒ `lrwxr-xr-x … /Users/chrisren/.claude-next/projects ->
/Users/chrisren/.claude/projects`, while `~/.claude-next` itself is a real directory (1,244 entries). `readlink -f`
on the two ROOTS returns two distinct real paths, so nothing is deduped, and step 4's slug-directed probe
`<root>/projects/<slug>/<sid>.jsonl*` returns **the same physical file twice** for every `next`/`.claude` session —
the exact trap P3 § 0 names ("Trap 1 — symlink double-count") and dedupes by uuid to avoid. It inflates `copies=N`
(rendered in § 5's row 1 as `copies=3` and in its reason string as "death record in copy 2/3"), doubles the
per-copy assistant-record counts that the BLOCKED rule unions over, and can make the preferred-`tp` tie-break pick
between two names for one inode.

**Fix.** Dedupe on `os.path.realpath(<root>/projects)` (or by `(st_dev, st_ino)` per candidate file), not on the
account root.

---

## 5. W1 changes the beat that `capacity-admit` consumes, and no DoD in the plan runs the capacity suites

**What.** § 1's fourth defect and § 8's R1 both say the point of `kind:"limited"` is to move
`capacity-admit.sh:782-792`'s arithmetic (ACTIVE 10 → 7 ⇒ ADMIT). W1's DoD names `stop-failure-marker.bats`,
`spawn-presence.bats`, `session-beat.bats`, `session-registry.bats` — and the § 4 gate rule is *"`bats tests/` for
the **touched** suites"*, which by file-touch excludes every consumer. But `tests/capacity-admit-active.bats`
(**22 tests**) writes beats with an explicit `kind` in its own helper (`:107-111`) and reasons about the semantics
W1 changes in words at `:265` (*"a crash leaves its `kind:"prompt"` beat on disk"*); `tests/capacity-admit-coverage.bats`
(**15 tests**) also reads beats. 37 tests over the arithmetic this wave exists to move, none named anywhere in
SYNTHESIS.md (`grep -c capacity-admit.bats SYNTHESIS.md` ⇒ 0).

**Fix.** Add `tests/capacity-admit-active.bats tests/capacity-admit-coverage.bats` to W1's DoD line, and change the
gate rule from "touched suites" to "touched suites ∪ suites that read the changed store".

---

## 6. The F2 degradation check adds a measured +0.09 s to a budget whose own worst measurement already sits at 0.24 s

**What.** § 2.3's fix for judge F2 is *"the census reads the live IDL's last 20,000 rows"* every invocation, purely
to render the DEGRADED footer. `~/.claude/autonomy/idl.jsonl` is **23.3 MB**; its last 20,000 rows are **4.59 MB**,
and parsing them costs **real 0.09 s** (measured this unit, one `/usr/bin/time -p python3` over a 5 MB tail seek).
The 0.07 s prototype never paid it. judge-Db-latency measured the winning design at **0.20–0.24 s wall at load
50.7**; the plan's bar (§ 4 W2a, § 5) is **≤ 0.30 s**. 0.24 + 0.09 ≈ 0.33 s — the bar is breached by the fix, at a
load this box reached today, and the DoD's own fixture (9 marker rows, a hermetic IDL) can never show it.

**Fix.** Bound the IDL read by TIME not row count (seek back to the window's start, typically a few hundred KB), or
make the abstain/DEGRADED probe a `--strict` flag and let the footer report `enumerator: unchecked` by default.

---

## 7. D3 raises `CAP` 500 → 5000 and creates an enumerate regime 350× the one every latency number was measured on — and its TTL argument is half already-true

**What.** Marker rows today: `wc -l ~/.claude/autonomy/stop-failure/*.jsonl` ⇒ **57 total** (next4 36, next3 12,
next 4, auth 5). D3(a) permits **5000 per cause file** (the plan's own worst case "≤ 2.5 MB per cause file"), i.e.
~20,000 rows across the live files, re-parsed in full on every census (the `--since 24h` filter is applied after
the read). No § 4 or § 5 row runs the census against a CAP-sized marker set; the drill fixture is 9 rows.
Separately, the TTL half of D3 is weaker than stated: the GC is `find "$MARKER_DIR" -type f -name '*.jsonl' -mmin
"+$TTL_MIN" -delete` (`hooks/stop-failure-marker.sh:100`) — keyed on the **FILE's** mtime, not the row's. A busy
account's file is appended daily and therefore never expires at 1440 either, so "a weekly cap outlives its marker"
is already true wherever deaths keep happening; raising TTL only helps a file that has gone quiet, and in exchange
keeps a quiet account's entire history readable for 7 days.

**Fix.** Keep CAP at 500 (or add per-sid dedupe at read time) until one W2b row measures the census at CAP-sized
input, and re-state D3's TTL rationale as "quiet-account files only" so the next session does not re-derive it.

---

## 8. W1's latency DoD stubs the one arm it exists to gate

**What.** § 4 W1: *"`/usr/bin/time -p bash hooks/stop-failure-marker.sh < fixture` ×3 printed, each ≤ 0.30 s **with
the beat writer stubbed at its 3 s cap**"*. The beat is the heaviest thing W1 adds to the death path; stubbed, the
row measures a hook without it. The plan's own budget line concedes the shape — *"beat ≤ 3 s hard cap"* — so the
real worst case is 3 s + 0.14 s, an order of magnitude past the bar, and no arrangement of the fixture can turn
this row red for the regression it names. (The `~10 ms` typical is real but comes from Dc's design `:313`, not from
P4, which contains no timing measurement at all — `grep -E '[0-9]+ ?ms|real ' P4/receipts.md` ⇒ no output.)

**Fix.** Run the row twice — stubbed (≤ 0.30 s) **and** against the real `session-beat.sh` with a p95 bar derived
from a measurement taken in W1, and state which arm the 0.30 s belongs to.

---

## 9. D5 retires `lf_locate` while `--deep` — the only census path to the 21 % no-transcript / sdk-cli class — is defined as `exec lr-fleet --slow-scan`

**What.** W2a defines `--deep` as *"execs `lr-fleet --slow-scan` for the `-p`/sdk-cli deaths no marker sees"*, and
every default screen prints `(-p sessions: run --deep)`. D5(a) — the option the plan adopts — is *"`lf_locate`
stays as `--slow-scan` for ONE release, **then is retired** if the both-paths diff has stayed empty."* The diff
staying empty is a statement about the cases both paths cover; it says nothing about the class only the scanner
reaches. P1 § 2 measured the miss as `sdk-cli` (2 sessions, hook does fire but no marker path) and P1 § 10 measured
**24 of 113 StopFailure sids (21 %)** with no usable transcript in the other direction. Retiring `lf_locate` on an
empty parity diff therefore deletes `--deep`'s implementation and the footer becomes a pointer to nothing.

**Fix.** Make D5's retirement condition "the parity diff is empty **and** `--deep` has a non-`lf_locate`
implementation", or re-state D5 as option (c) keep-forever-as-`--deep`.

---

## 10. TEAMMATE is decided from a transcript that 21 % of the population does not have, and it is a 13th predicate copy

**What.** W2a step 9's first real row is `TEAMMATE ⇐ "agentName" in head-8 KB of the preferred copy`. For the
NO-TRANSCRIPT class (P1 § 10: 15 TRANSCRIPT-NOT-FOUND + 9 NO-API-ERROR-RECORD) there is no copy, so TEAMMATE can
never match and the row falls through to RECOVERABLE/NO-PANE — which the poller then parks or enqueues, past the
`teammate-skip` guard at `lr-reset-poller.sh:752` that exists to stop exactly that. P1 § 8 also records *"No
teammate session in the corpus has ever died on a cap"*, so the branch is unmeasured as well as unreachable.
Second half: the repo already ships `hooks/lib/agent-identity.sh` and `hooks/lib/origin-identity.sh` (both named in
the designs, `grep -c agent-identity.sh SYNTHESIS.md` ⇒ 0) — a raw `"agentName"` substring test is a new copy of an
identity predicate, and W4's lint only refuses new *limit* regexes.

**Fix.** Read teammate identity through `hooks/lib/agent-identity.sh` (or the marker's own payload, which the hook
can stamp at death for free), and give the no-transcript case an explicit `TEAMMATE-UNKNOWN` disposition that the
poller treats as skip, not as recoverable.

---

## 11. Five of the census's eleven sources have no named failure disposition

**What.** Exit 5 is defined as *"instrument unreadable (registry dir / marker dir / accounts.json / `ps`)"* — four
sources. Step 1 also reads `parked/`; step 7 reads `locks/`, `fleet/*/results.tsv`, `results/<sid>.json`,
`requests/<sid>.json` and `faults/<sid>.json`; W2c *writes* `faults/`. None of the five has a stated disposition
for unreadable/absent/corrupt, and the plan's own governing lesson (`lr-fleet.sh:441-447`, quoted in § 2.2) is that
a silent empty list at exit 0 reads to every consumer as *no blocked sessions*. The asymmetric one is `faults/`:
if `--reaper --persist` cannot write (the poller runs under launchd), the FAULT vanishes at the marker TTL and F3
— the judge FATAL this arm exists to close — is back.

**Fix.** One rule in W2a's header: a source that is absent is EMPTY-and-noted in the footer; a source that exists
and cannot be read or parsed is exit 5 (stdout empty) — and `--reaper --persist` failing to write is exit 6 with
the path named.

---

## 12. Which copy of `lr_predicate` a converged `cc-limited` imports is unspecified, and the two differ

**What.** W2a is *"`bin/cc-limited` … imports `lr_predicate` in-process"*, and W3 routes the poller at
`$LR/../../bin/cc-limited`. The live layer is a per-file symlink farm (verified: `~/.claude/scripts/limit-recover/`
holds 11 symlinks into the checkout, `.py` files included; `~/.claude/bin/cc-custody` likewise). Python's
`__file__`/`abspath` does **not** resolve symlinks and `realpath` does, so `sys.path` built from `abspath` reaches
`~/.claude/scripts/limit-recover/lr_predicate.py` (the converged copy) and one built from `realpath` reaches the
**checkout tip** — two different code versions whenever the live layer lags trunk, with no error either way.

**Fix.** State it in the W2a brief — `os.path.realpath(__file__)` if the module must match the binary, `abspath` if
it must match the converged layer — and pin it with a W2b row that runs `cc-limited` through a symlink.

---

## 13. Two W5 acceptance rows cannot go red

**What.** (a) *"`bats tests/statusline-identity.bats`"* — P6 R10 quotes that suite verbatim at `:55`:
*"Historical certification. It cannot go red for a change to `statusline.sh`, by design."* It pins two historical
commits resolved from git by content, so naming it as a DoD gate is naming a no-op; only the `+10` new tests gate
anything. (b) *"30 renders under `getrusage` printed, CPU delta within ±3 ms of baseline"* — a tolerance band on a
loaded box, against a change P6 measured at **−0.2 ms**; the band is 15× the effect, so no plausible regression in
a 5-line env-read can breach it, and no mutant can turn it red.

**Fix.** Drop the historical suite from the DoD (keep it as a "must stay green" note) and replace the ±3 ms band
with the assertion that actually protects the property — `fork count == baseline` (P6: "zero `$(...)`, zero
backticks, zero pipelines").

---

## 14. F6 pins a wire format two units call UNMEASURABLE

**What.** W0's DoD lists *"F6 spend packet"* as a red-proof fixture and the predicate emits `monthly_spend` with
`recoverable_by_waiting=False`. P1 § 3 is titled *"`monthly_spend` does not exist as a cap class — UNMEASURABLE,
not covered"* and P3 § 6 says *"UNMEASURABLE whether 2.1.260 emits `quotaLimits` for this class — no monthly_spend
event"*. A fixture for a record nobody has seen pins a guessed string; if the real packet differs, the predicate
fails closed into `other` on the one cap class that can never be waited out.

**Fix.** Mark F6 in the suite as SYNTHETIC with its source (the `lr-reset-poller.sh:566 SPEND_RE` string it is
modelled on) and add the falsifier — first real monthly_spend record re-opens F6 — rather than presenting it as a
measured row beside F1–F5.

---

## 15. Wave 5's converge has a blast radius wider than the frozen scope says

**What.** The frozen scope ends *"Nothing here … edits `settings*.json`/plists/launchd"*, and § 6 says operator
steps are NONE. Wave 5 runs the granted `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`, which on an
ADVANCE runs `install.sh`, whose COPY classes are (verbatim, `scripts/deploy-live.sh:1311`) *"githooks/,
launchd/\*.plist, statusline.sh, bin/it2-wrapper→bin/it2, CLAUDE.md"*. So the step the plan takes to converge a
5-line statusline chip also rewrites githooks, CLAUDE.md and every plist under `launchd/` from the checkout.
(Checked and NOT a defect for this project's own daemon: the poller plist is not a launchd/ copy class —
`ls launchd/ | grep -i reset-poller` ⇒ rc 1 — so the § 6 operator `plutil` edit survives an install.)

**Fix.** Add one line to W5: run `bash scripts/deploy-parity-assert.sh` **before** the converge too, so the diff
the advance will apply to the other copy classes is seen and named rather than discovered afterwards.

---

## R — receipts (all read-only, run by this unit, 2026-09-19)

- `ls ~/.claude/cc-registry/` ⇒ 38 `*.json` + 5 `.stale-*`; **no `147.json`**. `cd ~/.claude/cc-registry && grep -l
  '07e30aeb\|09e64dcb\|98f02458\|4bc1159f' *.json` ⇒ **rc 1** (no match). `cat 111.json` ⇒ sid `cb29ae36…`,
  `claude-secondary`, pid 12341, `startedAt 1789857366000`; `cat 121.json` ⇒ `65186f1f…`, pid 59379,
  `1789850919000` — both exactly as § 5 states. `ps -o pid= -p 84167` ⇒ empty (dead now).
- `ls -ld ~/.claude-next/projects ~/.claude/projects` ⇒ `lrwxr-xr-x … .claude-next/projects -> …/.claude/projects`;
  `~/.claude-next` itself is a real dir (`ls -la ~/.claude-next` ⇒ 1,244 entries, `.claude.json` a real file).
- `ls -ld ~/.claude{,-next,-secondary,-tertiary,-quaternary}/autonomy` ⇒ four symlinks onto `~/.claude/autonomy`;
  `grep -n MARKER_DIR hooks/stop-failure-marker.sh:39` ⇒ `"${STOP_FAILURE_MARKER_DIR:-$HOME/.claude/autonomy/stop-failure}"`
  — HOME-anchored, so the marker store is single and **not** double-counted (checked; no finding).
- `wc -l ~/.claude/autonomy/stop-failure/*.jsonl` ⇒ 5 / 4 / 12 / 36 = **57**. `hooks/stop-failure-marker.sh:100`
  ⇒ `find "$MARKER_DIR" -type f -name '*.jsonl' -mmin "+$TTL_MIN" -delete` (file mtime, not row).
- `cat ~/.reso/limit-recover/parked/*.json` ⇒ 8 files, shape `{sid,acct,cfg,cwd,kind:"weekly",reset_at_utc,parked_at}`.
- `ls -la ~/.claude/autonomy/idl.jsonl` ⇒ **23,301,775 B**; `tail -20000 | wc -c` ⇒ **4,587,430 B**;
  `/usr/bin/time -p python3` seek-5 MB + `json.loads` of the last 20,000 rows ⇒ `parsed 19999`, **real 0.09**.
- `grep -c '@test' tests/capacity-admit-active.bats tests/capacity-admit-coverage.bats` ⇒ **22** and **15**;
  `grep -n kind tests/capacity-admit-active.bats` ⇒ `:107` helper `$3=kind`, `:111` jq `kind:$k`, `:265` the
  `kind:"prompt"` crash argument. `grep -c capacity-admit.bats SYNTHESIS.md` ⇒ **0**.
- `ls -la ~/.claude/scripts/limit-recover/` ⇒ 11 symlinks into `…/Development/claude-infrastructure/scripts/limit-recover/`
  incl. `lr-audit.py`, `lr-select.py`; `ls -la ~/.claude/bin/cc-custody` ⇒ symlink. `sed -n 110,131p
  hooks/stop-failure-marker.sh` ⇒ the jq object carries `config_dir:$cfg` (so § 1's `acct_death` field DOES exist —
  checked, no finding).
- `sed -n 1305,1340p scripts/deploy-live.sh` ⇒ `:1311` the COPY-class list; `ls launchd/ | grep -i reset-poller`
  ⇒ rc 1; `ls -la ~/Library/LaunchAgents/com.reso.lr-reset-poller.plist` ⇒ present, 798 B, Jul 18.
- `sed -n 35,48p .claude/CLAUDE.md` ⇒ the `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` grant, as § 3 W5 states.
- Corpus reads: `wave2/SYNTHESIS.md` in full; `P1 §§ 10-12`, `P2` headers, `P3` headers, `P4` (full grep for timing
  ⇒ none), `P5 R4-R5`, `P6 R1/R7-R10`, `P7` headers, `P8` headers, `P9` headers, `P10` headers;
  `judge-Db-latency/receipts.md`, `Jb-correctness/judgment.md` F1-F3 headers; design file-path census over
  `lr/design/D1..D3`.
