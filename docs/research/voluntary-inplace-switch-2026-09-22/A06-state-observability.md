# A06 — State machine, verdict lane and evidence trail for a VOLUNTARY in-place account switch

Read-only investigation, 2026-09-22. Every claim is `file:line` or a live-store census; nothing in
the repo or in `~/.reso` / `~/.claude` was modified, and no notification was sent.

---

## 0. Verdict

**Today's stores cannot express a voluntary move, and the failure is not a missing enum — it is that
every admission gate, every clause and every verdict token is derived from a QUOTA FACT the
voluntary move does not have.** Three independent chokepoints refuse or lie:

| chokepoint | what it requires | what a voluntary move has |
|---|---|---|
| `bin/cc-lr:267-270` → `bin/cc-find:150-155` | `cf_class` = `LIMITED` (last assistant record is a usage-limit api error) | class `SESSION` ⇒ **rc 2, nothing started** |
| `scripts/limit-recover/lr-ingest-verify.sh:165-168` (clause A4) | `audit.json .last_api_error.kind ∈ {session, weekly, monthly_spend}` | `ABSENT` ⇒ **FAIL A4 ⇒ rc 1** |
| `scripts/limit-recover/lr-fleet.sh:807` | `verdict` initialised to `RECOVERED` before any outcome is measured | nothing was broken ⇒ **the word is false and the value is unearned** |

And a fourth, quieter one: there is **no terminal-OK state in the store at all**. `bin/cc-lr:406`
admits `RECOVERED|DONE|ENGAGED|engaged` as the `ok` class; `lr-reset-poller.sh:1303-1306` records
that no writer in the tree emits any of them; a census of every `events.jsonl` on this box returns
**0** occurrences (§2.5). So the rendering class that would say "this finished cleanly" is
unreachable for the involuntary lane too — a voluntary lane cannot be grafted onto it without
fixing that first.

**The single most load-bearing positive finding** (§4.4): the verdict lane already works for an
in-place move, and it works for a reason nobody wrote down — the inbox is **pane-keyed**
(`~/.claude/mailbox/<paneUUID>.md`, `hooks/mailbox-drain.sh:36`) and every account's `mailbox/`
is a **symlink to `~/.claude/mailbox`** (measured). A successor that comes up in the same pane on a
*different account* drains the same inbox, exactly-once via the split `.seen`/`.acked` cursor. Any
design that keys the verdict on the SID instead of the pane loses the mail on the recycle variant,
where the sid changes.

---

## 1. There are TWO voluntary moves, and the brief's claim differs for each

The brief's target claim — *"this session is now on account X, same pane"* — is ambiguous between
two rails that exist today, have different stores, different vocabularies, and different
falsifiability requirements. Everything below is split on this axis.

| | **VOLUNTARY-TRANSPLANT** | **VOLUNTARY-RECYCLE** |
|---|---|---|
| Rail | `lr-handoff.sh --in-place --target <acct>` (`lr-handoff.sh:250`, `:329-341`) | `handoff-fire.sh --recycle --account <acct>` (`handoff-fire.sh:8847`, `:9736-9737`) |
| Session identity | **preserved** — same sid, transcript copied to the target config dir (`transplant.json`, `lr-transplant.sh`) | **destroyed** — `prev_sid` → new sid (measured in `handoffs.jsonl`, §2.3) |
| Context | preserved | fresh |
| Pane | same | same |
| Store written | `~/.reso/limit-recover/<sid>/bundle-<TS>/events.jsonl` | `~/.claude/logs/handoffs.jsonl` |
| Visible to `cc-lr status` | yes | **no** |
| Visible to `handoffs.jsonl` consumers | only the two watcher rows, with `account:null` | yes |
| Claim it can support | "same session, same pane, now on X" | "same pane, a NEW session, now on X" |

`lr-handoff`'s own commit message names the voluntary case explicitly: *"the commonest in-place
recovery on this box, **a session moving itself to a fresher account**"* (`git show e508b2344`,
2026-09-22). The voluntary move is not hypothetical — it is already the modal traffic, wearing a
recovery's clothes.

---

## 2. (a) Today's vocabulary, with `file:line`, and what is wrong for a voluntary move

### 2.1 Run-state vocabulary — `events.jsonl`, written by `lr_state_append` (`lr-lib.sh:441`)

Record shape (`lr-lib.sh:461-463`): `{ts, run, state, stage, detail, writer, attempt}`. Readers take
the LAST line (`lr_state_current`, `lr-lib.sh:471`), with terminal stickiness against a later
non-terminal line from a stale writer (`lr-lib.sh:425-426`, enforced in the renderer at
`bin/cc-lr:428-430`).

| state | emitted at | `cc-lr` class (`bin/cc-lr:406-407`) | meaning for a VOLUNTARY move |
|---|---|---|---|
| `REFUSED` | `lr-handoff.sh:760` (handoff-fire unreachable) | bad | fine — actuator-level |
| `<state>` from handoff-fire precheck | `lr-handoff.sh:769` (`${state%%:*}`) | varies | **unbounded**: the precheck's vocabulary leaks into this store verbatim. A value nobody mapped lands in `klass()`'s `return "run"` default, i.e. renders as "in progress" forever |
| `probed` | `lr-handoff.sh:791` (driver verb), `:819` (self verb, landed `e508b2344`) | run | detail carries `killed_inflight=<n>` — see §6 gap 11 |
| `PARKED` | `lr-handoff.sh:832` (capacity) | bad | correct, but indistinguishable from "stranded" downstream (§6 gap 6) |
| `admitted` | `lr-handoff.sh:839` | run | fine |
| `gate-admitted` / `gate-absent` | `lr-fire-resume.sh:431` / `:434` | run | fine |
| `submit-token-armed` | `lr-fire-resume.sh:468` | run | fine — this is the token that makes engagement observable (§4.3) |
| `relaunch-typed` | `lr-fire-resume.sh:651` | run | fine |
| `READY-QUIET` / `READY-NOT-SEEN` | `lr-fire-resume.sh:858` / `:867` | run | fine |
| `SUBMIT-RECR` / `SUBMIT-UNMEASURED` | `lr-fire-resume.sh:917` / `:959` | run | fine |
| `submitted` / `queued` | `lr-fire-resume.sh:969` / `:972` | run | **`submitted` is the real terminal success and it is classed `run`** — the successor took the prompt, and the renderer still shows the run as in-flight |
| `INDETERMINATE:submit` | `lr-fire-resume.sh:975` | bad | correct polarity (unmeasured ≠ negative) |
| `FAILED:submit` | `lr-fire-resume.sh:980` | bad | fine |
| `FAILED` | `lr-fire-resume.sh:74` | bad | fine |
| `RECOVERED` / `DONE` / `ENGAGED` | **nothing emits these** — `lr-reset-poller.sh:1303-1306`, confirmed by census (§2.5) | ok | the entire OK class is dead code in both lanes |

**Wrong for a voluntary move, specifically:** nothing in this vocabulary carries a CAUSE, so the
store cannot distinguish "moved because quota died" from "moved because I chose to". The cause lives
one file away, in `audit.json.last_api_error.kind`, and is consumed only as an admission predicate
(§2.4) — never recorded as a property of the run.

### 2.2 Verdict vocabulary — the mail line (`lr-fleet.sh:1141-1171`)

Composed at `lr-fleet.sh:1163`:

```
lr-fleet --one <sid8>: verdict=<V> rc=<n> pane=<p> acct=<a> mech=<m>[ engagement=UNAWAITED] — <note>; evidence: <dir>
```

Written to `$FLEET_DIR/$RUN/verdict.txt` (`:1164`) and mailed via `cc-notify` to
`$LR_FLEET_REQUESTER`, falling back to `--role desk` (`:1167-1168`). The token map (`:1149-1154`)
reads **column 6 of `results.tsv`**, which is `"<mech>/<verdict>"` (`lf_row`, `lr-fleet.sh:837,851`):

| col-6 value | mailed `verdict=` | source | correct for a voluntary move? |
|---|---|---|---|
| `recycle-in-place/RECOVERED` | `RECOVERED` | `lr-fleet.sh:807,1150` | **No.** Nothing was recovered. And the value is the *initialiser*, set before any outcome is read, downgraded only on `rc ≠ 0` — so it means "lr-handoff returned 0", not "the session is running on X" |
| `…/PARTIAL` | `PARTIAL` | `:816,1151` | conflates two opposite states (§6 gap 6) |
| `parked` | `PARKED` | `:761,765,779,789,1152` | closest to "I chose not to move", but reads as a failure of the actuator |
| `` (empty row) | `FAILED` | `:1153` | fine |
| **`dry-run`** | **`FAILED`** | `:769` → `*)` at `:1154` | **polarity defect**: a dry run mails a failure |
| **`skipped` / `skipped/by-design`** | **`FAILED`** | `:990,998-1000` → `*)` at `:1154` | **polarity defect**: a by-design no-op mails a failure. For a voluntary lane, "I decided not to move" is the commonest non-move |

`engagement=UNAWAITED` (`:1162`) is appended only when `LR_INPLACE_AWAIT=0` *and* the verdict is
`RECOVERED` — an honest qualifier, but it is a **suffix on a success token**, not its own verdict, so
any consumer matching `verdict=RECOVERED` reads a proven move where none was measured.

### 2.3 The other vocabulary — `handoffs.jsonl` classes (`handoff-fire.sh:821 emit_recycle_event`)

This is the store the **VOLUNTARY-RECYCLE** lane actually writes, and `cc-lr` cannot see it.

`recycle-intent` (`:12249`) · `recycle-engaged` (`:7301`) · `recycle-submitted` (`:7285`) ·
`recycle-unverified` (`:7265`) · `recycle-dead` (`:7009, :7031, :7124, :7329, :7378`) ·
`recycle-refused-no-shell` (`:12304`) · `recycle-held-draft` (`:12359, :12364, :12531`) ·
`recycle-residue-scrubbed` (`:12355`) · `recycle-nudge-held` (`:6999`) ·
`recycle-bgwork-answered` (`:6963`).

Measured over the live log (30-day file, `~/.claude/logs/handoffs.jsonl`): `admitted` 810 ·
`refused` 166 · `self-retire-peer` 12 · `recycle-intent` 10 · `goal-arm` 9 · `recycle-engaged` 6 ·
`recycle-dead` 4 · `trim` 3 · `recycle-nudge-held` 3.

**The outcome rows carry `account: null`.** Measured on the 8 most recent recycle rows: every
`recycle-engaged` / `recycle-dead` row has `account:null` and `firing_sid:null` (they are written by
the detached watcher, which has neither). Only `recycle-intent` carries an account, and on the
lr-handoff path its value is the literal string **`(explicit launcher)`** (`handoff-fire.sh:9963`).
**So `handoffs.jsonl` cannot today answer "which account is this pane now on" from any outcome row.**

### 2.4 The admission clauses that structurally refuse a voluntary move

`lr-ingest-verify.sh` runs 14 clauses and composes the successor's first user prompt from them
(`:556-570`). Each is judged here for a voluntary move:

| clause | predicate | file:line | voluntary verdict |
|---|---|---|---|
| A1 | `MANIFEST.gaps_at_handoff == 0` | `:142-143` | **valid** — reusable verbatim |
| A2 | `audit.counts.gaps == 0 && .waiting == 0` | `:150-153` | **valid, and MORE load-bearing**: for a voluntary move this is the whole safety argument |
| A3 | delegations `open==0`, `spawned==settled` | `:155-163` | **valid** |
| A4 | `last_api_error.kind ∈ {session,weekly,monthly_spend}` | `:165-168` | **STRUCTURALLY WRONG** — `ABSENT` ⇒ FAIL ⇒ rc 1. There is no value meaning "no error, by choice" |
| A5 | `teams.led` RUNNING members == 0 | `:170-177` | **valid** |
| A6 | `events.jsonl` carries explicit `killed_inflight=<n>`, and `n==0` | `:179-226` | **semantically inverted** — see §6 gap 11 |
| B1 | re-audit finds no NEW non-success notification since the bundle | — | **valid** |
| C1 | 3-way agreement: `$CLAUDE_CONFIG_DIR` == `MANIFEST.target_cfg` == account-map(`target`) | `:293, :309-318` | **valid and is the account oracle** (§4.2) |
| C2 | target transcript exists | — | **valid** |
| C3 | split-brain lock names the target | — | **valid** |
| C4 | source tombstoned | — | **valid**, but see §6 gap 6 — tombstoning is exactly what makes a failure STRANDED rather than NOTMOVED |
| C5 | branch | — | **valid** |
| D1 / D2 | no foreign armed auto-continue at the source / target key | `:540-553` | **valid** |

**12 of 14 clauses are correct for a voluntary move.** Only A4 and A6 are quota-shaped. That is the
measured size of the problem: this is a two-clause defect wearing a whole-subsystem's clothes.

The prose the PASS path composes is also false for a voluntary move. `lr-ingest-verify.sh:566-568`
types into the successor's composer:

> `Resumed in place on <target> — same pane, same session <sid8>, after a <kind>-limit <status> on <acct>.`

`<kind>` and `<status>` are read from `audit.json.last_api_error` (`:165`, `:562`). On a voluntary
move that clause asserts an interruption that never happened — and it enters the successor's own
context **as its first user turn**, i.e. the false cause becomes the successor's belief about its
own history.

### 2.5 Measured coverage of the evidence trail that exists today

| measurement | value | command |
|---|---|---|
| bundle dirs under `~/.reso/limit-recover/*/bundle-*/` | **75** | `ls -d ~/.reso/limit-recover/*/bundle-*/ \| wc -l` |
| of those, carrying `events.jsonl` | **7** | `ls ~/.reso/limit-recover/*/bundle-*/events.jsonl \| wc -l` |
| `RECOVERED\|DONE\|ENGAGED` states ever written | **0** | `cat …/events.jsonl \| jq -r .state \| grep -cE '^(RECOVERED\|DONE\|ENGAGED\|engaged)$'` |
| `INGEST-VERIFIED.txt` receipts on disk | **3** | `ls ~/.reso/limit-recover/*/bundle-*/INGEST-VERIFIED.txt` |
| of those, reading `rc 0` | **0** — all three read `rc 1 (first failure: A6)` | `grep -h '^verdict:' …/INGEST-VERIFIED.txt \| sort \| uniq -c` |
| distinct states ever written | `admitted` 6 · `gate-admitted` 6 · `submit-token-armed` 6 · `relaunch-typed` 4 · `FAILED:submit` 4 · `SUBMIT-UNMEASURED` 3 | `… \| jq -r .state \| sort \| uniq -c` |

**The evidence trail has never once produced a clean verdict.** Any proposal that assumes the
involuntary lane's receipt works and merely needs a voluntary variant is building on a receipt with
a 0/3 success rate.

---

## 3. (b) The proposed voluntary vocabulary, verdict contract, and `cc-lr status` rendering

### 3.1 The discriminator is a FIELD, not a state value

**Do not encode "voluntary" as a new `state` token.** `bin/cc-lr:406-408`'s `klass()` has a
permissive default (`return "run"`), so an unrecognised state silently becomes "in progress" — the
repo's `closed-vocabulary-swallows-an-unrecognized-value` shape, and the failure direction is the
worst one (a completed voluntary move renders as a run in flight, forever).

Encode it as **two new fields on `MANIFEST.json`**, beside the `in_place` / `in_place_implied` pair
already there (`lr-handoff.sh:637-644`):

| field | values | why |
|---|---|---|
| `trigger` | `involuntary` · `voluntary` | the axis every clause and every verdict must branch on |
| `reason` | `quota-limit` · `context-ceiling` · `auth-cliff` · `rebalance` · `model` · `operator` | the CAUSE, recorded as a property of the run rather than re-derived from `audit.json` at read time |

`reason` subsumes A4's predicate and makes it a *consistency* check rather than an admission gate:
A4 becomes "`reason=quota-limit` ⟺ `last_api_error.kind ∈ {session,weekly,monthly_spend}`", which
PASSES on a voluntary move (both sides absent) and still catches a mislabelled one.

Precedent for writing a field ahead of its reader is already in the tree and is explicitly annotated
as such — `cc-lr`'s repair-request `.mode` key, *"NOT READ BY THE POLLER ON THIS TREE — written per
the W5 spec so the field is there when W5-A's reader lands"* (`bin/cc-lr:~455-462`). **But the
precedent carries a hazard**: a field written and never read is indistinguishable from a field read
and always empty (the `approved 0 · unknown 3,359` shape). So: land the emitter, the `klass()` arm,
and a test that RED-fails if `trigger` is absent, in one change.

### 3.2 State / event vocabulary — additions only

Existing states are lane-agnostic and stay. Three additions, all terminal:

| state | when emitted | who reads it | why it is needed |
|---|---|---|---|
| `SWITCHED` | the successor's first `type:"user"` record carrying `LR_SUBMIT_TOKEN` is observed in the TARGET transcript — i.e. the same probe that today writes `submitted` (`lr-fire-resume.sh:969`), promoted to terminal when `trigger=voluntary` | `cc-lr status` (`klass()` `ok`); `wrap-ledger` (§5); the poller's retire arm (`lr-reset-poller.sh:1315`) | there is no terminal-OK state today (§2.5) and the renderer has an unreachable `ok` class |
| `NOTMOVED` | the run decided not to move, and **nothing was mutated**: no transplant, no tombstone, no `/exit` | `cc-lr status` (new `hold` class — see §3.4); `wrap-ledger` | must be distinguishable from a failure; today it maps to `FAILED` or `PARKED` (§2.2) |
| `STRANDED` | the source WAS retired (tombstone written / `/exit` sent) and no live registry row names the sid after the run | `cc-lr status` (`bad`); `wrap-ledger` (the one arm that earns a 🔧) | the dangerous outcome, which today is `PARTIAL` and shares a token with benign ones |

`SWITCHED` also needs `bin/cc-lr:406` extended, and `lr-reset-poller.sh:1315`'s
`[[ "$_lrp_st" == RECOVERED ]]` widened — otherwise the new terminal is invisible to the retire arm
exactly as `RECOVERED` is today.

**Do not add a `CHOSE`/`INTENT` non-terminal state.** `admitted` (`lr-handoff.sh:839`) already marks
the first durable transition and `gate-admitted` the second; a third pre-flight token adds a row and
no bit.

### 3.3 The verdict contract

The mail line is the only surface a peer or the desk sees. It must satisfy four properties, three of
which today's line fails:

1. **A parseable `verdict=` token** — already satisfied (`lr-fleet.sh:1141-1143`).
2. **The token must name the OUTCOME, not the actuator's exit code.** Today `RECOVERED` is the
   initialiser (`:807`).
3. **The line must carry the CLAIM's own subject.** The claim is about account identity, so the line
   must carry `from=` and `to=`. Today it carries `acct=$acct` — the SOURCE only (`:1163`) — while
   `results.tsv` col 4/5 already hold `acct_before`/`acct_after` (`lf_row`, `:851`) and are simply
   not folded in. A verdict that cannot be checked against its own subject is the
   `discharge-predicate-must-measure-its-own-subject` defect.
4. **The token set must partition on ACTION, not on severity.** Two outcomes that demand opposite
   next actions may not share a token.

Proposed line (voluntary lane):

```
lr-switch <sid8>: verdict=<V> kind=voluntary reason=<R> from=<acctA> to=<acctB> pane=<p> sid=<sid8> proven=<yes|no> rc=<n> — <note>; evidence: <bundle dir>
```

| `verdict=` | means | the operator/peer's next action | replaces |
|---|---|---|---|
| `SWITCHED` | move complete AND a turn was observed on the target (`proven=yes`) | none | `RECOVERED` |
| `SWITCHED-UNPROVEN` | move complete structurally; engagement not measured (`proven=no`) | read `cc-lr status <sid8>`; the pane may be at a bare shell | today's `RECOVERED engagement=UNAWAITED` suffix |
| `NOTMOVED` | refused / parked / dry-run / by-design skip. **Source untouched and still working.** | nothing, or retry later | today's `PARKED`, and the `dry-run`/`skipped` rows that wrongly map to `FAILED` |
| `STRANDED` | source retired, successor absent. **Work is at risk.** | rescue: the bundle holds the transcript and the tombstone names the target | today's `PARTIAL` |
| `FAILED` | the actuator itself errored before deciding anything | read `<bundle>/<sid>.stderr` | `FAILED` |

`proven=` is a separate field from the token deliberately: collapsing it into the token would give
five tokens × two proof states = ten, and the alarm-polarity law says a token set that fine stops
being read. `proven` is the field a consumer branches on; the token is what a human scans.

**`NOTMOVED` vs `STRANDED` is the load-bearing split**, and the line that decides it already exists:
`lr-ingest-verify.sh`'s C4 (source tombstoned). Before the tombstone a failure is `NOTMOVED`; after
it, `STRANDED`. Record the tombstone write as its own `events.jsonl` transition so the split is
computable from the log alone rather than from a filesystem race.

### 3.4 How `cc-lr status` renders a voluntary run without confusing it with a recovery

`cmd_status` (`bin/cc-lr:347-457`) renders `RUN | STATE | AGE | CAUSE / NEXT` from one bulk `jq` over
every `events.jsonl` (`cl_events_bulk`, `:341`). Three changes, all inside the existing `awk`:

1. **A `KIND` column, read from the run's `MANIFEST.json`.** Not from the state token — §3.1. Values
   `vol` / `rec` / `?`. `?` is a POSITIVE finding (a run whose manifest is unreadable), rendered as
   `?`, never defaulted to `rec`: defaulting would make every pre-change bundle claim to be a
   recovery, which is true today but becomes a lie the moment both lanes coexist.
2. **A third class beside `ok` / `run` / `bad`: `hold`.** `NOTMOVED` is neither a success nor a
   failure; it is a decision. Rendering it `bad` re-creates the alarm-polarity defect at the
   renderer after fixing it at the mail.
3. **The `NEXT` column must not prescribe `cc-lr repair` for a voluntary run.** Today every `bad`
   run with a live session gets `→ cc-lr repair <bundle>` (`:441-443`). `repair` re-types a prompt
   into a pane; for `NOTMOVED` the source session is *still working on its original account* and
   re-typing into it is a corruption, not a repair. The `NEXT` for a voluntary `NOTMOVED` is
   literally *"nothing — the source pane is unchanged and still on `<from>`"*.

`cc-lr status` also has **no `--json`**. The wrap-ledger integration in §5 needs a machine read, and
re-deriving the last-line + terminal-stickiness rule in a second consumer is the
`sibling-auditors-must-share-the-state-model` defect this file already avoided once
(`bin/cc-lr:68-73`). **Add `cc-lr status --json` in the same change**, emitting one object per run
with `{run, sid, bundle, kind, state, klass, age_s, cause, next, manifest:{trigger,reason,from,to,pane}}`.

---

## 4. (c) The evidence directory and the minimum falsifiable artifact set

### 4.1 Directory: reuse the bundle, do not mint a parallel tree

`~/.reso/limit-recover/<sid>/bundle-<TS>/` (`lr-handoff.sh:489`). `lr-lib.sh:423-425` records the
reasoning for keeping the run's state in its own bundle rather than a shared index — *"D2-FT #16
refused an `index.jsonl` upsert: an unlocked read-modify-write loses updates"*. That argument is
unchanged for a voluntary run. A `~/.reso/voluntary-switch/` tree would also split the store
`cc-lr status` scans, which `bin/cc-lr:38-46` already names as the hazard it refuses to paper over.

Artifacts present today in a real bundle (measured, `2825e1e5/bundle-20260922T155240Z`):
`audit.json` · `audit.md` · `events.jsonl` · `git-log.txt` · `git-status.txt` · `HANDOFF-CONTEXT.md`
· `INGEST-VERIFIED.txt` · `lr-launch-<sid8>-<rand>.sh` · `MANIFEST.json` · `salvage/` ·
`transplant.json` · `workflow-scripts/`.

Plus two artifacts OUTSIDE the bundle that the claim rests on:
`~/.reso/limit-recover/locks/<sid>.lock` (`{sid, from, to, ts, pid, host, owner, ts_first, chain}`)
and the source-side tombstone `<source_cfg>/projects/<slug>/<sid>.HANDOFF.json`
(`{handed_off_to, target_transcript, ts, lock}`).

### 4.2 What makes "this session is now on account X, same pane" falsifiable by a third party LATER

The claim has three independent halves, and today only two have a durable artifact.

| half of the claim | the artifact that proves it | durable? |
|---|---|---|
| "**this session**" — identity continuity | `MANIFEST.transcript_sha256` (a hash of the transcript taken BEFORE the move) + `transplant.json.sha256` of the file at the target path | **yes** — both are already written and are content hashes, not pointers |
| "**is now on account X**" | `~/.claude/cc-registry/<pane>.json` `.account` + `.session_id` | **NO — this is the gap** |
| "**same pane**" | same registry row's `.paneUUID`; `lr-fleet.sh:827-836` already reads it back after the run | **no, for the same reason** |

**Why the registry cannot serve as the later proof.** `hooks/session-register.sh:9-13` fixes the
registry at `$HOME/.claude/cc-registry/<paneUUID>.json` — deliberately account-agnostic and
deliberately NOT under `$CLAUDE_CONFIG_DIR`, which is what makes it the cross-account addressing
table and what makes its `.account` field authoritative for "which account is this pane on **now**".
But the file is **pane-keyed and rewritten on every SessionStart** — `lr-fleet.sh:820-826` states it
in as many words: *"The registry row is REWRITTEN on every SessionStart (startup, resume, compact),
so reading it back after the run is the one cheap check whose failure means exactly what it says."*
A store that is rewritten on every session start answers "now" by destroying "then". The next
recycle of that pane — minutes later — erases the only record that the account ever changed.

`lr-fleet.sh:827-836` **performs exactly the right read and then throws the row away**, keeping only
`cut -f1` (the pane id).

### 4.3 The minimum falsifiable set — four artifacts, one of them new

| # | artifact | status | what it makes falsifiable |
|---|---|---|---|
| 1 | `MANIFEST.json` extended with `trigger`, `reason`, and an explicit `source_acct` / `target_acct` pair | **extend** (`lr-handoff.sh:637-644`) | who moved, from where, to where, why, when — in one file |
| 2 | `events.jsonl` with a terminal `SWITCHED` / `NOTMOVED` / `STRANDED` | **extend** | the transition sequence, append-only, size-bounded, jq-encoded (`lr-lib.sh:441-467`) |
| 3 | `SWITCH-VERIFIED.txt` — the clause ladder, `lr-ingest-verify.sh` run with `trigger=voluntary` (A4 becomes a consistency check, A6 an advisory) | **extend** the existing receipt | that the move's preconditions held, clause by clause, with a first-failure id |
| 4 | **`registry-after.json`** — a verbatim copy of `~/.claude/cc-registry/<pane>.json`, plus the read timestamp and the reader's own `$CLAUDE_CONFIG_DIR` | **NEW** | **"now on account X"** — the only artifact that survives the next SessionStart |

Artifact 4 is the whole answer to "falsifiable by a third party later", and it costs one `cp` at
`lr-fleet.sh:830`, where the row is already in hand.

**And the claim needs a fourth leg that none of these four give: that the successor actually took a
turn.** `LR_SUBMIT_TOKEN` already exists for this (`lr-fire-resume.sh:468`,
`lr-ingest-verify.sh:562-568`) — the submit probe looks for the token in a `type:"user"` record of
the TARGET transcript, which distinguishes a prompt that reached the composer from one typed into a
pane nobody was reading. Record the token in `MANIFEST.json` so a third party can re-run the grep.

**The re-derive line, written INTO the bundle** (a receipt whose command is not written down decays
— `published-figure-decays-with-its-source`). One file, `REDERIVE.txt`:

```
jq -r '.sid, .source_cfg, .target_cfg, .source_pane, .submit_token' MANIFEST.json
test -f "$(jq -r .target_transcript transplant.json)"                       # the bytes arrived
shasum -a 256 "$(jq -r .target_transcript transplant.json)"                 # == MANIFEST.transcript_sha256 at move time
grep -c "$(jq -r .submit_token MANIFEST.json)" "$(jq -r .target_transcript transplant.json)"   # >=1 ⇒ a turn was taken THERE
jq -r '.account, .session_id, .paneUUID' registry-after.json                # the account claim, as captured
jq -r '.account, .session_id' ~/.claude/cc-registry/"$(jq -r .source_pane MANIFEST.json)".json  # the account claim, NOW
```

The last two lines are the point: a third party compares the **captured** row against the **live**
row and can say whether the pane is still on the target or has since moved again. With only the live
row, both a successful switch and a later re-switch read identically.

### 4.4 The verdict lane works for an in-place move — and the reason must not be broken

`bin/cc-lr:7-9` and `lr-fleet.sh:1033` record the cost that banned foreground polling: *"recovering
five sessions cost 98.7 minutes of which 24.4 were the LEAD's own foreground polling"* — 17 polls on
2026-09-19. The replacement is the async mail lane (`lr-fleet.sh:1141-1171` → `cc-notify` →
`hooks/mailbox-drain.sh`).

For an in-place move the requester pane and the target pane are **the same pane**, so a naive reading
says the verdict is mailed to the session being replaced. It is not lost, and the reason is
structural:

- the inbox is **pane-keyed**: `~/.claude/mailbox/<own-pane-uuid>.md` (`hooks/mailbox-drain.sh:36`);
- measured: `~/.claude-secondary/mailbox` and `~/.claude-tertiary/mailbox` are **symlinks to
  `~/.claude/mailbox`**, so the inbox is one store across all accounts;
- delivery is exactly-once via a split cursor, `.seen` advanced at drain and `.acked` promoted one
  cycle later at the next Stop, **dup-biased by design** (`mailbox-drain.sh:11-17`) — a death between
  drain and Stop re-surfaces the line rather than silently consuming it.

So a successor that comes up in the same pane **on a different account** drains the same inbox and
sees the verdict at its next boundary. This is why the async lane is viable for a voluntary in-place
switch at all, and it is a property to state in the design rather than rediscover: **any lane keyed
on the SID loses the mail on the VOLUNTARY-RECYCLE variant, where the sid changes by construction.**

---

## 5. (d) Interaction with the close ledger — visible, as FIELDS, never as a rung

### 5.1 The answer, and the precedent it rests on

**Yes, visible. As reported fields. Never as a rung — with exactly one exception.**

`scripts/wrap-ledger.sh:154-175` § GOAL states the governing law for precisely this shape:

> *REPORTED, NEVER A RUNG. A live `/goal` is a normal state of a working session, so a rung on it
> would fire at every close of every goal-armed session — the alarm-polarity law that already bounds
> 👤, ⛔ and 🚀 here. What was missing is not a verdict but a MEASUREMENT.*

A completed voluntary switch is the same kind of object: a normal state of a healthy session, with
nothing owed by anyone. A rung on it would fire at every close of every switched session and carry
zero bits. The same law is applied to `BUSY` at `wrap-ledger.sh:2125-2127` (*"FIELDS, NEVER A RUNG:
busy-ness is orthogonal to the ladder"*).

### 5.2 The one exception that DOES earn a rung

`SWITCHED-UNPROVEN` and `STRANDED` are a loose end **this session caused and only this session can
close** — the same shape as the custody arm at `wrap-ledger.sh:996-1009`, which folds an unreturned
dispatched session into 🔧 on the argument that *"in-flight dispatched work IS a loose end"*.

Proposed arm, ranked **beside** the custody arm (`:1998-2009`) and immediately below it:

```
RUNG=🔧 iff SWITCH_SRC=voluntary AND SWITCH_SID == this session's sid AND SWITCH_PROVEN=0
```

`SWITCH_PROVEN=?` (unreadable) must **never** produce a rung — same fail direction as
`CUSTODY_SRC=error` (`:1082-1083`) and `YOURS_SRC=none`.

### 5.3 The fields

Emitted by `emit_machine()` (`wrap-ledger.sh:2168-2230`), after the `CUSTODY_*` block:

| field | values | notes |
|---|---|---|
| `SWITCH_SRC` | `none` · `error` · `absent` · `voluntary` · `involuntary` | `absent` is a POSITIVE finding and is never manufactured from a read that did not happen — the law stated for `GOAL_SRC` at `:174-176` and for `YOURS_SRC=none` |
| `SWITCH_SID` | sid8 of the run, or `-` | makes the arm attributable; a sibling's switch in a shared checkout may never convict this pane (the `session-writes.sh` attribution principle) |
| `SWITCH_FROM` / `SWITCH_TO` | account names | the claim's subject; without them the field says nothing checkable |
| `SWITCH_REASON` | from `MANIFEST.reason` | |
| `SWITCH_VERDICT` | `SWITCHED` · `SWITCHED-UNPROVEN` · `NOTMOVED` · `STRANDED` · `FAILED` · `-` | relayed from the run's terminal state, **never re-derived** (`consume-don't-re-derive`, stated at `:2204-2206`) |
| `SWITCH_PROVEN` | `1` · `0` · `?` | |
| `SWITCH_EVIDENCE` | bundle path | S5 of the close message |
| `SWITCH_AGE_MIN` | minutes since the terminal transition | lets a consumer suppress an ancient switch |

**Read it through `cc-lr status --json` (§3.4), bounded** by `_bounded "${WRAP_SWITCH_TIMEOUT_S:-5}"`
exactly as the custody / backlog / decide reads are (`:1063`, `:1081`), failing to `SWITCH_SRC=error`.
Do not re-implement the last-line/terminal-stickiness rule inside `wrap-ledger.sh`.

### 5.4 Where it lands in the close message

- **S1 (state line)** — only when the switch happened THIS TURN, and then only as the subject clause
  ("what the work WAS"), never as the rung.
- **S4 (outcome)** — "now running on `<to>`, same pane, same session" — if and only if
  `SWITCH_PROVEN=1`.
- **S5 (evidence)** — `SWITCH_EVIDENCE`, the bundle path. This is the slot that makes the drop legal:
  a close that mentions a switch without naming the bundle has deleted the detail, not dropped it.
- **S2 (verdict)** — `SWITCHED-UNPROVEN` / `STRANDED` forces `Good to close: no — <what remains>`.

---

## 6. Gap list — what today's stores CANNOT express for a voluntary move

| # | gap | evidence |
|---|---|---|
| 1 | **No "nothing was broken" cause.** The only cause field is `audit.json.last_api_error.kind`, consumed as an admission predicate requiring `session\|weekly\|monthly_spend`. No value means "no error, by choice" | `lr-ingest-verify.sh:165-168` |
| 2 | **No terminal-OK state is ever written, in either lane.** The renderer's `ok` class admits `RECOVERED\|DONE\|ENGAGED\|engaged`; nothing emits any of them; measured 0/7 events logs | `bin/cc-lr:406`; `lr-reset-poller.sh:1303-1306`; census §2.5 |
| 3 | **`verdict=RECOVERED` is doubly wrong**: the word is false for a voluntary move, and the value is an initialiser set before any outcome is read, downgraded only on `rc ≠ 0` | `lr-fleet.sh:807, 814-818` |
| 4 | **The verdict line cannot name the destination account.** It carries `acct=<source>`; `results.tsv` col 5 already holds `acct_after` and is not folded in | `lr-fleet.sh:837, 851, 1163` |
| 5 | **Polarity defect in the token map:** `dry-run` and `skipped`/`skipped/by-design` fall through `*)` to `verdict=FAILED`. A by-design no-op mails a failure | `lr-fleet.sh:769, 990, 998-1000, 1154` |
| 6 | **`PARKED` / `PARTIAL` cannot separate "nothing moved, source intact" from "source retired, successor absent".** The two demand opposite actions (retry vs rescue). The discriminator — whether C4's tombstone was written — is not recorded as a transition | `lr-fleet.sh:761-789, 816, 1151-1152`; `lr-ingest-verify.sh` C4 |
| 7 | **No store records an account CHANGE.** `~/.claude/logs/account-assignments.jsonl` is append-only but carries only `{t, ts, acct, src}` — no sid, no pane, no `from`. `~/.claude/cc-registry/<pane>.json` carries `account`+`session_id` but is pane-keyed and rewritten every SessionStart. `handoffs.jsonl` outcome rows carry `account:null` | measured (§2.3, §4.2); `hooks/session-register.sh:9-13, 172`; `lr-fleet.sh:820-826` |
| 8 | **Two vocabularies over one phenomenon.** A voluntary move via `handoff-fire --recycle --account` writes 10 `recycle-*` classes to `handoffs.jsonl` and NO `events.jsonl`, so `cc-lr status` cannot see it at all; a move via `lr-handoff --in-place` writes `events.jsonl` and reaches `handoffs.jsonl` only as two watcher rows with `account:null` | §1, §2.3 |
| 9 | **The admission path refuses a voluntary move outright.** `cc-lr recover` exits 2 unless `cf_class` = `LIMITED`; a healthy session classes `SESSION`. The refusal's own text names the cause: *"every downstream rail (recycle, transplant, tombstone, self-close) is gated on the quota predicate"* | `bin/cc-lr:203, 267-270`; `bin/cc-find:150-155` |
| 10 | **No machine read of a run.** `cc-lr status` prints a table only; a consumer must re-implement last-line + terminal-stickiness, which is the two-auditors-one-population defect the file itself warns about | `bin/cc-lr:68-73, 347-457` |
| 11 | **A6's `killed_inflight` is semantically inverted for a voluntary move.** It measures what the recycle will KILL. For an involuntary move that is a receipt; for a voluntary one it is a **reason not to move**, and no arm anywhere refuses on it — a FAIL only makes the launcher keep the long ingest prompt, while the move proceeds | `lr-ingest-verify.sh:179-226`; `lr-handoff.sh:772-819` |
| 12 | **The composed successor prompt asserts an unmeasured cause.** `"after a <kind>-limit <status> on <acct>"` is read from `last_api_error` and typed into the successor's composer as its first user turn — so on a voluntary move the false cause becomes the successor's own belief about its history | `lr-ingest-verify.sh:562-568` |
| 13 | **The existing receipt has never produced a clean verdict.** 3 `INGEST-VERIFIED.txt` on disk, all `rc 1 (first failure: A6)`; 7 of 75 bundles carry `events.jsonl` at all | census §2.5 |
| 14 | **`MANIFEST.in_place` already exists and carries none of this.** It is a boolean about the MECHANISM (same pane), with a sibling `in_place_implied` about how it was chosen — and nothing about the trigger, the cause, or the accounts as a pair | `lr-handoff.sh:637-644`; live manifest §4.1 |

---

## 7. Adversarial pass

Three challenges run against the draft, each with a real tool call, each changing the answer.

**"You assumed the voluntary lane is limit-recover's. It isn't."** — Correct, and this was the
largest correction. `handoff-fire.sh --recycle --account <other>` already performs a voluntary
same-pane account change today and is measurably used (`recycle-intent` rows carrying
`account:"next3"` in the live log). It writes a completely different store with a completely
different vocabulary and is invisible to `cc-lr`. The report is now split on that axis throughout
(§1) and it is gap 8. Consequence for the design: a voluntary-move spec that lives only in the
limit-recover tree will describe the minority path — the same failure shape as a cap that saw only
Agent spawns.

**"You assumed the registry proves the account."** — It proves it *now* and destroys *then*.
`hooks/session-register.sh:9-13` fixes the registry at `$HOME/.claude/cc-registry/<paneUUID>.json`,
account-agnostic by design — so `.account` IS authoritative — but `lr-fleet.sh:820-826` states that
the row is rewritten on every SessionStart, including resume and compact. A pane-keyed row
overwritten on every session start cannot answer a question asked later. This produced artifact 4
(§4.3), the one genuinely new thing the design needs, and it costs one `cp` at a line that already
holds the row.

**"A verdict mailed into the pane being replaced is a mail to a dead session."** — Refuted, and the
refutation is load-bearing. The inbox is pane-keyed (`hooks/mailbox-drain.sh:36`) and every account's
`mailbox/` is a symlink to `~/.claude/mailbox` (measured), with a dup-biased split cursor
(`:11-17`). The successor — different account, same pane — drains the same inbox at its next
boundary. This is *why* the async lane substitutes for the banned 24.4-minute poll on an in-place
move, and it is the property that forbids keying the lane on sid (§4.4).

**Residual I could not close.** Whether `cf_class` should gain a fourth class (e.g. `HEALTHY`) or
whether the voluntary lane should bypass `cc-find` entirely is a `bin/cc-limited` census-contract
question, and `bin/cc-lr:195-197` records that it belongs to `LIMIT_DETECT_100P` and is **an open
operator call on an unowned plan whose lead died**. Naming it here rather than deciding it.

---

## 8. Re-derive (every number in this file)

```bash
# state vocabulary actually written, and coverage
jq -r .state ~/.reso/limit-recover/*/bundle-*/events.jsonl | sort | uniq -c | sort -rn
ls -d ~/.reso/limit-recover/*/bundle-*/ | wc -l
ls    ~/.reso/limit-recover/*/bundle-*/events.jsonl | wc -l
grep -h '^verdict:' ~/.reso/limit-recover/*/bundle-*/INGEST-VERIFIED.txt | sort | uniq -c

# the OK class is unreachable
jq -r .state ~/.reso/limit-recover/*/bundle-*/events.jsonl | grep -cE '^(RECOVERED|DONE|ENGAGED|engaged)$'

# handoffs.jsonl class census, and the null-account outcome rows
jq -r .class ~/.claude/logs/handoffs.jsonl | sort | uniq -c | sort -rn
jq -rc 'select(.class|test("recycle"))|[.class,.account,.prev_sid,.target_pane]|@tsv' ~/.claude/logs/handoffs.jsonl | tail -8

# the mailbox is one pane-keyed store across all accounts
ls -ld ~/.claude/mailbox ~/.claude-secondary/mailbox ~/.claude-tertiary/mailbox

# the registry is account-agnostic, pane-keyed, and rewritten every SessionStart
cat ~/.claude/cc-registry/*.json | head -2
sed -n '9,13p;172p' ~/.claude/hooks/session-register.sh
```
