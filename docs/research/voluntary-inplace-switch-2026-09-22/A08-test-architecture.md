# A08 — Test architecture for a VOLUNTARY in-place account switch

**Verdict on the test problem: the transplant and the recycle are already account-agnostic and already well covered; the whole new test surface is the ADMISSION boundary and three safety gates that were written under a premise a voluntary move falsifies.** The mechanics need equivalence guards, not red proofs. The gates need red proofs, and two of them can be built hermetically today.

The load-bearing mechanical finding, which sets the shape of everything below:

> `scripts/handoff-fire.sh:9716-9722` — `if [ "$RCY_TRANSPLANTED_SOURCE" = 1 ] && [ "$ALLOW_LIVE_SA" = 0 ]; then ALLOW_LIVE_SA=1`, justified in its own comment as *"A limit-blocked lead's subagents died with it."* That premise is FALSE for a voluntary move of a healthy session. The subagent gate (`:5156-5199`, exit 4) is the only thing standing between a recycle and a mid-run SIGKILL of in-flight Agent-tool units, and the transplanted-source class disarms it unconditionally.

---

## 1. What a voluntary switch actually moves — the four admission sites

| # | Site | Today's rule | Voluntary needs |
|---|---|---|---|
| A1 | `bin/cc-lr:178-266` `cl_refuse_not_limited` | RULE 2: a non-LIMITED session is refused rc 2, no mutex (`:202` states *"NO in-place recycle exists for this class — every downstream rail … is gated on the quota predicate"*) | an explicit voluntary verb that is admitted, with RULE 0 (teammate) and RULE 1 (ambiguous) still binding |
| A2 | `scripts/handoff-fire.sh:7833-7835` `prp_verdict "REFUSED:not-limited" 5` | the read-only probe REFUSES a healthy pane | a voluntary mode where the limit clause abstains and clauses 1/3/4/5 (registry · teammate · pane-state · composer) still refuse |
| A3 | `scripts/limit-recover/lr-handoff.sh:797-823` the SELF arm | already ignores the probe rc by design — a self-recovery of a healthy session ALREADY works (`lr-handoff.sh:805-810`) | nothing; this is the one site voluntary already has. The DRIVER arm (`:762-769`) still vetoes on rc |
| A4 | `scripts/handoff-fire.sh:9716-9722` | `--transplanted-source` ⇒ `ALLOW_LIVE_SA=1` | the implication must be conditioned on the recovery CLASS, not on the flag |

`scripts/limit-recover/lr-transplant.sh` is **intent-free end to end** — it never reads a transcript's api-error class, only `--from`/`--to`, the custody lock and the tombstone. `scripts/limit-recover/lr-fire-resume.sh` likewise carries no limit predicate (its launch line is `… --resume $sid`, `:725/:727`). So the *movement* needs no new code and no new tests beyond equivalence guards; only the *decision* does.

---

## 2. (a) Coverage inventory — what is asserted, and what is not

### `bin/cc-lr` — `tests/cc-lr-front.bats` (38 cases, 633 lines)

| Asserted | Where |
|---|---|
| RULE 0 teammate refusal, by its OWN message (`lead-owned`), mutant-hardened against RULE 2 answering for it | `tests/cc-lr-front.bats:91-106` |
| RULE 1 ambiguous refusal, every candidate printed, no mutex | `:107-117` |
| RULE 2 not-LIMITED refusal + the 2026-09-22 routing text + the `CC_LR_ROUTE_REFUSAL=off` byte-for-byte control | `:118-187` |
| mutex take / live-holder refuse / dead-holder steal / TTL / release-on-refusal | `:209-272` |
| iron rule (never types, never kills, never git, launchctl only kickstarts) **with a positive control on each banned verb** | `:596-624` |

| **NOT asserted** | Consequence for this wave |
|---|---|
| No case admits ANY session at rc 0 that is not `LIMITED`. `:159` (*"recover REFUSES a genuinely working session"*) is the case a voluntary verb must not break — it becomes an equivalence guard, not a red proof. | the whole voluntary admission is new surface |
| The split-store hazard `bin/cc-lr` documents at `:38-45` (`LR_STATE_DIR` honoured here, hardcoded `$HOME` at `lr-handoff.sh:489` and `lr-reset-poller.sh:127`) is prose with no test | a voluntary run under a non-default `LR_STATE_DIR` writes its bundle where `cc-lr status` does not look |

### `scripts/limit-recover/lr-handoff.sh`

| Asserted | Where |
|---|---|
| `lrh_resolve_implied_pane` in all five outcomes (explicit · SELF kitty · SELF iTerm2 prefix-strip · DRIVER single row · two rows REFUSED · no row rc 1) | `tests/lr-handoff-inplace-default.bats:48-104` |
| `LRH_SELF_PANE` is exported and is *not* `SOURCE_PANE` | `:65-84` |
| `lrh_precheck` DRIVER arm records `killed_inflight` from the probe's count, value-checked | `tests/lr-handoff-launcher-quoting.bats:586-606` |
| `lrh_precheck` SELF arm records it too, and a probe REFUSAL does not veto the transplant | `:608-648` (this case's liveness assertion `output == *"self probe on pane 505"*` is the model for every new SELF case) |
| `--close-source` preconditions, the four spawn arms' successor-id capture, "no pane id ⇒ no close" | `tests/lr-handoff-close-source.bats:162-300` |
| `--source-pane` registry binding + three controls | `:340-402` |

| **NOT asserted** | Consequence |
|---|---|
| The suite says so itself: *"WHAT IT DOES NOT PIN … the ENABLING CONDITIONS at the call site (`--spawn` / `--print-only` / `--no-transplant` / `--close-source` / no `--launch` / `LR_INPLACE_DEFAULT=off`) are a single guarded `if`"* — `tests/lr-handoff-inplace-default.bats:13-18`, and the guard is `lr-handoff.sh:317-327` | a voluntary flag adds a SIXTH term to that same `if`; it lands in the one block the suite declares untested |
| No case drives the DRIVER arm's `rc -ne 0 → return 6` (`lr-handoff.sh:766-769`) against `REFUSED:not-limited` | the asymmetry between the SELF arm (admits a healthy session) and the DRIVER arm (refuses one) is undocumented by any test |
| No case asserts what `--in-place` does when `killed_inflight > 0` — it is RECORDED and never a refusal (`handoff-fire.sh:7761`) | for a voluntary move this is the live-loss path |

### `scripts/limit-recover/lr-transplant.sh` — `tests/lr-transplant.bats` (16 cases)

Asserted: same-target idempotence over all three refusal sites (`:42-97`), custody hops incl. third hop / `ts_first` / symlinked `--from` / pre-W5-B lock (`:107-233`), `LR_STATE_DIR` honoured by the WRITER (`:224`), source retirement with `CLAUDE_CODE_SESSION_ID` unset (`:234`), `--force` × custody independence (`:256-284`), and clause C3 of the ingest verifier (`:302-326`).

**NOT asserted:** `--task-list` copying, the `rsync` of `<sid>/` (subagents, workflows, journals), and anything that would distinguish a voluntary move from a forced one — correctly, because the script has no such concept. Everything here is an equivalence guard for this wave.

### `scripts/handoff-fire.sh` recycle arm

| Asserted | Where |
|---|---|
| the remote in-place resume's full precondition ladder (registry row · row pid alive · row pid on the pane's tty · tombstone · `handed_off_to` ≠ this cfg · lock still held · `--resume-cfg` = the tombstone's target), each with its own refusal | `tests/handoff-recycle-remote-resume.bats:113-295` |
| `--transplanted-source` ⇒ `--allow-live-subagents`, **positively** | `:147-154` |
| the probe's cross-root transcript search, two roots, subject in the FIRST | `tests/handoff-probe-preconditions.bats:67-106` |
| the probe writes NOTHING (tree byte-identical) | `:95-106` |

| **NOT asserted** | Consequence |
|---|---|
| **No negative case for `:9716-9722`.** Nothing proves the subagent gate still refuses when it should on this class. A test that passes with and without the auto-allow is an equivalence guard (`docs/lessons/green-in-both-arms-is-an-equivalence-guard-not-a-red-proof.md`) — and that is the only kind of case the suite has | the single highest-severity hole |
| No probe case reaches gates 4 (pane state) or 5 (composer). `tests/handoff-probe-preconditions.bats:70-73` says outright the verdict "may legitimately be a later refusal (there is no real pane here)" | a voluntary probe mode changes gate 2; nothing pins that gates 4/5 still fire after it |
| The bgwork modal auto-answer (`handoff-fire.sh:3113-3121`, `:6919-6960`, choice = KEEP via `hooks/lib/pane-modal.sh:268`) is tested for its READ (`tests/handoff-recycle-bgwork-dialog.bats`) and never for whether it should run at all on a session with genuinely live background work | a voluntary recycle answers an operator's dialog unaudited |

---

## 3. (b) Seams, and exactly where hermeticity breaks

### Seams that exist and work

| Seam | Env var | What it fakes | Proven by |
|---|---|---|---|
| session resolver | `CC_LR_FIND_BIN` | `cc-find`'s TSV + rc (0/1/2) | `tests/cc-lr-front.bats:27,38-47` |
| recovery driver | `CC_LR_FLEET_BIN` | `lr-fleet.sh --one … --detach` argv capture | `:28,48-58` |
| state store | `LR_STATE_DIR` | bundles, mutexes, requests, custody locks | `:22`; writer honours it at `lr-transplant.sh:78` |
| registry row (pane ⇄ session) | `CC_REGISTRY_DIR` | `hooks/session-start.sh`'s `<pane>.json` | `tests/handoff-probe-preconditions.bats:50-53` |
| account stores | `CC_PROJECTS_DIRS` (space-separated, **≥2 roots or the test is blind**) | the five `~/.claude*/projects` roots | `:55-58`; the bug it caught is `handoff-fire.sh:7796-7806` |
| the actuator, from lr-handoff | `CC_HANDOFF_FIRE_BIN` | probe verdict + rc, and the whole fire | `tests/lr-handoff-close-source.bats:98`; probe-stub helper `stub_hf` in `tests/lr-handoff-launcher-quoting.bats` |
| lr-handoff's siblings (`lr-transplant.sh`, `lr-audit.py`, `lr-fire-resume.sh`, `lr-preseed-env.sh`) | fixtured `$HOME` only — `lr-handoff.sh:191` hardcodes `LR="$HOME/.claude/scripts/limit-recover"` | the transplant, the audit, the launcher | `tests/lr-handoff-close-source.bats:110-133` |
| launcher parser preflight | `LRH_LIVE_PARSER_CHECK=off` | the live `lr-fire-resume` parse gate | `:43` |
| capacity / admission | `CC_FIRE_CAPACITY_GATE=off`, `CC_ADMIT_GATE=off`, `CC_FIRE_HEADROOM_GATE=off`, `CC_ACCOUNTS_BIN=<absent path>`, `HANDOFF_ACCOUNT_SWEEP_STAMP`, `CC_HEAL_LOCK_PREFIX` | ambient box load — **mandatory**, see §6 | `tests/handoff-probe-preconditions.bats:41-47` |
| terminal | `CC_TERM=iterm2` + `IT2_WRAPPER_NO_KITTY=1` + `unset KITTY_WINDOW_ID`, PATH shims for `osascript` / `ps` / `kitty`, `CC_TERM_KITTY`, `CC_TERM_KITTY_TO`, `IT2_BIN` | pane resolution, typing, composer read | `tests/handoff-recycle-remote-resume.bats:28-79` |
| tty query failure injection | `HANDOFF_TTY_FAIL_FILE`, `HANDOFF_TTY_RETRIES`, `HANDOFF_TTY_RETRY_SLEEP_S` | bridge hiccups vs a genuinely absent pane | `handoff-fire.sh:1612-1618` |
| subagent census | `CC_PROJECTS_DIRS` + `<slug>/<sid>/subagents/agent-*.meta.json` + `agent-*.jsonl` without `"stop_reason":"end_turn"` | in-flight Agent-tool units | `handoff-fire.sh:5086-5148` |
| the gate itself | `CC_RECYCLE_SUBAGENT_GATE=off` | kill switch — **use it only as a control arm, never to make a case pass** | `:5159-5161` |
| guard self-identity | `CC_HOG_SELF_PID` | "am I the live copy" ancestry walk | `hooks/handed-off-session-guard.sh:106` |
| no-side-effect mode | `--dry-run` | runs **every** gate incl. `subagent_gate` (`:9724`) and prints the mode line (`:12609`) before any keystroke | `tests/handoff-recycle-remote-resume.bats:113-165` |

### Where hermeticity BREAKS — the third-program boundary

`docs/lessons/a-fixture-s-hermeticity-ends-where-its-subject-spawns-a-third-tool.md` is the binding lesson. Enumerated for this subject:

| Break | Site | Reaches the real machine? | Containment |
|---|---|---|---|
| `python3` × 2 (realpath, chain parse) | `lr-transplant.sh:38,91` | no — pure computation on fixture paths | none needed; but a stub MUST carry a shebang or CPython keeps walking `$PATH` (`docs/lessons/a-shebang-less-stub-seals-only-the-shell-arm.md`) |
| `rsync`, `shasum`, `hostname -s` | `lr-transplant.sh:249,259-260,242` | filesystem only, inside fixtures | ok |
| `ps` — three distinct query forms | `handoff-fire.sh:3775-3776` (`-o pid= -t`, `-o tpgid= -t`), `:3792` (`-o pid=,comm= -g`), `:3779` (`-axo pid=,ppid=`), `:1594` (`-o tty= -p`) | **YES** — the live process table | PATH shim answering by *form*, per `tests/handoff-recycle-remote-resume.bats:64-77` and the richer one at `tests/handoff-selfclose.bats:89-160` |
| `osascript` / `kitty @` | `handoff-fire.sh:1612-1640`, `hf_remote_pane_term` `:2114` | **YES** — the operator's terminal | PATH shim + `CC_TERM`/`IT2_WRAPPER_NO_KITTY` |
| `it2` (`session read`, `session send`) | `composer_content` `:2604-2607`, `pane_bgwork_key` `:3113-3121` | **YES** — writes into a live pane | `IT2_BIN` pin to a stub; `tests/lr-handoff-close-source.bats:85-87` asserts the it2 log EMPTY as a safety property |
| `jq` | `lr-handoff.sh:379` | no, but its ABSENCE is a refusal path worth a case | `command -v jq` guard already there |
| `launchctl` | `bin/cc-lr` kickstart, `lr-fleet.sh` | **YES** | PATH stub, `tests/cc-lr-front.bats:59-66` |
| `git` | `handoff-fire.sh` worktree freshness | **YES** | PATH stub returning 0 |

**A `pid`/pane-id fixture is a claim about a wrapping namespace** (`docs/lessons/a-fixture-s-pid-range-is-a-claim-about-a-shared-wrapping-namespa.md`). `tests/handoff-recycle-remote-resume.bats` already closes that world through the `ps` shim rather than by picking "impossible" pids — copy that, never a hardcoded high pid. Pane ids in new fixtures must also survive `scripts/pane-id-lint.sh` (see §6).

---

## 4. (c) Proposed test cases — each with the mutant whose death proves it live

Severity: **S1** = a voluntary switch silently destroys work · **S2** = admission is wrong · **S3** = record/consumer integrity.

| # | Test name | Suite file | What it proves | The MUTANT it kills |
|---|---|---|---|---|
| **T1** | `voluntary: the subagent gate still REFUSES — a healthy session's in-flight units are not the ingest's to re-audit` | `tests/handoff-recycle-voluntary-class.bats` (new) | `--recycle --transplanted-source --voluntary --dry-run` with one live `agent-*.meta.json` exits 4 and names the unit | delete the class condition added at `handoff-fire.sh:9716` so `--transplanted-source` alone re-implies `ALLOW_LIVE_SA=1` → T1 passes-to-fail. **S1** |
| **T2** | `CONTROL: the LIMIT class still auto-allows — the 2026-09-09 recovery is unchanged` | same | the forced class (no `--voluntary`) still prints `re-audited by the ingest, not protected here` with the same fixture | invert the condition (auto-allow only on voluntary) → T2 dies. T1+T2 together are the two-sided pin; either alone is an equivalence guard |
| **T3** | `voluntary: an explicit --allow-live-subagents is still the operator's door` | same | with the flag, the same fixture proceeds and emits the `override` admit row (`:5197-5198`) | hard-refuse voluntary over any live subagent → T3 dies. Proves T1 is a gate, not a ban. **S1** |
| **T4** | `voluntary probe: the limit clause ABSTAINS and prints why; clauses 1,3,4,5 still refuse` | `tests/handoff-probe-preconditions.bats` (extend) | `--probe-recycle-preconditions --voluntary` on a healthy transcript does **not** emit `REFUSED:not-limited`; the same run on a teammate transcript still exits 5 `REFUSED:teammate` | make `--voluntary` skip the whole gate block rather than just clause 2 → the teammate arm passes → T4 dies. **S2** |
| **T5** | `voluntary probe: live_subagents is still printed on EVERY path, including the abstain` | `tests/handoff-probe-preconditions.bats` | the count line (`:7820-7823`) survives the new branch | move the count back below the limit gate (the exact 2026-09-22 defect) → T5 dies. **S3** |
| **T6** | `voluntary probe: STILL writes nothing — the fixture tree is byte-identical` | `tests/handoff-probe-preconditions.bats` | re-runs the existing `:95` shape under `--voluntary` | any implementation that records the voluntary intent from inside the probe → T6 dies. **S3** |
| **T7** | `cc-lr: an explicit voluntary verb is ADMITTED on a healthy session, takes the mutex, and fires --one` | `tests/cc-lr-front.bats` (extend) | rc 0, mutex created, `fleet.argv` carries the voluntary flag | delete the admission arm → T7 dies. Pair with T8/T9 or it licenses a bypass. **S2** |
| **T8** | `cc-lr: the voluntary verb does NOT weaken RULE 0 — a teammate is still refused with 'lead-owned'` | `tests/cc-lr-front.bats` | the teammate refusal fires ahead of the voluntary admission | reorder so the voluntary admission precedes RULE 0 → T8 dies. `:91-106`'s own comment records that a `*TEAMMATE*` assertion already SURVIVED a mutant — assert `lead-owned` and the ABSENCE of `not LIMITED`. **S1** |
| **T9** | `cc-lr: the voluntary verb does NOT weaken RULE 1 — an ambiguous ref is still refused, nothing created` | `tests/cc-lr-front.bats` | rc 2, both candidates printed, no mutex, no fleet call | move the ambiguity check after the voluntary branch → T9 dies. **S2** |
| **T10** | `cc-lr: the BARE recover verb on a healthy session still refuses byte-for-byte` | `tests/cc-lr-front.bats` | `:159` and `:175` texts unchanged without the flag | make voluntary the default → T10 dies. This is the anti-metastasis pin. **S2** |
| **T11** | `voluntary: a session whose lead process is MID-TURN is REFUSED, not moved` | `tests/lr-handoff-voluntary-eligibility.bats` (new) | reuses `lr-audit.py`'s `lead_state` (`tests/lr-audit-nonlimit.bats:319` IN-FLIGHT) rather than inventing an idleness predicate | make UNKNOWN or IN-FLIGHT fall through to IDLE → T11 dies. Kills A10's objection 6 (sample-then-act) at the only place it is decidable. **S1** |
| **T12** | `voluntary: an UNKNOWN lead state is REFUSED — the instrument's silence is not an all-clear` | same | `LR_AUDIT_LEAD_STATE` forced (kill switch at `tests/lr-audit-nonlimit.bats:444`) | fail-open on UNKNOWN → T12 dies. `docs/lessons/fail-safe-default-mimics-the-healthy-state.md`. **S1** |
| **T13** | `voluntary: a live background-work modal on the source pane is HELD, never auto-answered` | `tests/handoff-recycle-voluntary-class.bats` | probe clause 5's screen already carries the dialog; assert `HELD:bgwork` rc 3 under voluntary and the existing auto-answer under the limit class | let `pane_bgwork_key` (`:3113`) run on the voluntary path → T13 dies. **S1** |
| **T14** | `voluntary: the enabling condition at lr-handoff's call site is the SIXTH term, and each of the other five still vetoes` | `tests/lr-handoff-inplace-default.bats` (extend) | drives `lr-handoff.sh:317-327` whole (not the sed-extracted resolver) with `--voluntary` × each of `--spawn` / `--print-only` / `--no-transplant` / `--close-source` / no-`--launch` | drop any conjunct from the guard → exactly one row of the table flips. This closes the hole the suite declares at `:13-18`. **S2** |
| **T15** | `voluntary: the DRIVER arm no longer vetoes on REFUSED:not-limited, and still vetoes on REFUSED:teammate` | `tests/lr-handoff-launcher-quoting.bats` (extend, beside `:608-648`) | `lr-handoff.sh:766-769` gains a class-aware rc read | make the driver arm ignore rc entirely (copying the SELF arm) → the teammate row passes → T15 dies. **S1** |
| **T16** | `voluntary: killed_inflight is recorded BEFORE the transplant and a non-zero value REFUSES` | same | today `killed_inflight` is recorded and never a refusal (`handoff-fire.sh:7761`); for voluntary, `lr-ingest-verify` clause A6 (`lr-ingest-verify.sh:215-226`) can only fail AFTER the loss | keep it record-only under voluntary → T16 dies. Turns a post-hoc ingest failure into a pre-transplant refusal. **S1** |
| **T17** | `voluntary: the tombstone still acquits the SUCCESSOR and still blocks the SOURCE` | `tests/handed-off-session-guard.bats` (extend) | a voluntary tombstone (whatever new field it carries) leaves `hooks/handed-off-session-guard.sh:63-68,146` fail-open parsing intact; the successor under the target cfg is acquitted by `case "$TP" in "$TARGET"/*)` | add the field in a way that breaks `handed_off_to` extraction → the successor's own prompts get blocked. **S3** |
| **T18** | `voluntary: the custody chain records the hop — a voluntary move is a hop like any other` | `tests/lr-transplant.bats` (extend) | equivalence guard, labelled as one: `--from B --to C` after a voluntary A→B keeps `ts_first` and the whole chain | none — **state in the test name that this is GREEN IN BOTH ARMS** (`tests/handoff-probe-preconditions.bats:25-28` is the precedent for labelling). **S3** |
| **T19** | `voluntary: the successor's launcher carries --resume, so an armed /goal is RESTORED` | `tests/handoff-recycle-voluntary-class.bats` | `lr-fire-resume.sh:725,727` spawn line ⇒ `tengu_goal_restored_on_resume`; the resume form itself prints `no goal inheritance` (`handoff-fire.sh:12609`) and that is correct only because `--resume` carries it | replace the launcher with a bare relaunch → T19 dies. Answers A10 objection 4's goal clause. **S2** |
| **T20** | `voluntary: `cc-lr status` finds the run's bundle under a NON-default LR_STATE_DIR` | `tests/cc-lr-front.bats` | the split store `bin/cc-lr:38-45` documents (`lr-handoff.sh:489` hardcodes `$HOME/.reso/limit-recover`) | none today — **this is a RED on the tree as it stands.** File it or fix `lr-handoff.sh:489` in the same wave; do not land a test that ratchets a known split. **S3** |

**Mutation-run discipline.** Build every mutant and run the **whole** suite against it, not just the case: `docs/lessons/one-dead-assertion-class-found-is-not-the-last-one.md` — a suite can carry two dead-assertion classes at once. Record per-case death in the wave report the way `tests/cc-lr-front.bats:10-15` already does.

---

## 5. Fixture / seam design

### New suite 1 — `tests/handoff-recycle-voluntary-class.bats` (T1,T2,T3,T13,T19)

Fork `tests/handoff-recycle-remote-resume.bats:26-112` verbatim; it is the only harness that drives `handoff-fire.sh --recycle` through every gate without typing. Required additions:

```
setup():
  export HOME="$BATS_TEST_TMPDIR/home"                 # hermeticity rule 1
  export CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off CC_FIRE_HEADROOM_GATE=off
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-accounts"
  export HANDOFF_ACCOUNT_SWEEP_STAMP=... CC_HEAL_LOCK_PREFIX=...
  export CC_REGISTRY_DIR=... CC_PROJECTS_DIRS="$ROOT_A $ROOT_B"   # TWO roots, subject in the FIRST
  export CC_TERM=iterm2 IT2_WRAPPER_NO_KITTY=1; unset KITTY_WINDOW_ID ITERM_SESSION_ID
  PATH shims: osascript (returns TTY-<uuid>), ps (answers -o tty= from $PS_TTY_OUT), git, it2, kitty
  export IT2_BIN="$SHIM/it2"                            # and assert its log EMPTY in every case
  run with --dry-run                                    # every gate runs; nothing is typed
```

The in-flight subagent fixture, which is the whole point of T1:

```
$ROOT_A/-repo/$SID/subagents/agent-aa.meta.json   {"description":"a live unit"}
$ROOT_A/-repo/$SID/subagents/agent-aa.jsonl       one record, NO "stop_reason":"end_turn"
$ROOT_A/-repo/$SID.jsonl                          no subagent stop record for agent-aa
```
`live_subagents_of` (`handoff-fire.sh:5086-5119`) then reports it IN FLIGHT via the fallback arm. `subagent_dir_for_sid` (`:5127-5148`) needs the **two-root** `CC_PROJECTS_DIRS` or the case is blind to the same address bug `tests/handoff-probe-preconditions.bats` was written for.

For T13, drive the bgwork modal off a **fixture screen** through the `it2 session read` shim, reusing the screen text in `tests/handoff-recycle-bgwork-dialog.bats` — never a real pane.

### New suite 2 — `tests/lr-handoff-voluntary-eligibility.bats` (T11,T12)

Reuse the harness primitives already in `tests/lr-handoff-launcher-quoting.bats`: `lrh_inplace_setup`, `mkrepo`, `lrh_row`, `lrh_tx`, `gen_inplace_self`, and above all `stub_hf '<probe stdout>' <rc>` — the probe stub is the one seam that makes the precheck drivable. Lead-state comes from a stubbed `lr-audit.py` at `$HOME/.claude/scripts/limit-recover/lr-audit.py` (the shape `tests/lr-handoff-close-source.bats:116-124` already uses), emitting `{"lead_state":"IN-FLIGHT"|"IDLE"|"UNKNOWN"}`.

**Every stub gets `#!/usr/bin/env bash` or `#!/bin/bash`.** A shebang-less stub seals the bash arm only; `lr-transplant.sh` and `lr-audit.py` are invoked from paths where a CPython `subprocess` would keep walking `$PATH` to the real binary (`docs/lessons/a-shebang-less-stub-seals-only-the-shell-arm.md`).

### Extensions rather than new files

T4,T5,T6 → `tests/handoff-probe-preconditions.bats` (it already owns the probe and its two-root fixture).
T7-T10,T20 → `tests/cc-lr-front.bats` (owns the three refusals and the `find_stub`/`fleet_stub`/`row` helpers at `:38-80`).
T14 → `tests/lr-handoff-inplace-default.bats`, but **invoked whole**, not through the sed-extracted resolver — the guard is at the call site, and `:31-34` extracts only `lrh_resolve_implied_pane`.
T15,T16 → `tests/lr-handoff-launcher-quoting.bats:574-670`.
T17 → `tests/handed-off-session-guard.bats`.
T18 → `tests/lr-transplant.bats`.

### Non-vacuity, per this repo's bar

- Every non-final `[[ ]]` / `[ ]` carries `|| false` (`tests/bats-shim-parity-lint.bats:19-20`).
- Negative assertions use the count form `[ "$(grep -c -- X f)" = 0 ]`, never `! grep` (`tests/lr-handoff-close-source.bats:28-29`).
- Every case that could pass because an arm never ran carries a **liveness assertion** naming a string only that arm prints — copy `tests/lr-handoff-launcher-quoting.bats:645-647` verbatim in spirit; it exists because that exact case once passed while the arm was dead.
- Assert the plan line. A bats run whose corpus half-executed exits 1 with ordinary `not ok` lines and no `1..N` mismatch visible to the caller (`tests/bats-shortfall-nonverdict.bats:3-20`); and a gate that REFUSES to run emits no TAP at all. When you run these suites by hand, read `1..N` before believing a green.

---

## 6. (d) Existing tests this change will touch or redden

| Test | Line | Why it fires | Disposition |
|---|---|---|---|
| `tests/cc-lr-front.bats` iron rule | `:596-601` — `[ "$(grep -cE '(^\|[^a-zA-Z_.-])kill[[:space:]]' "$LR")" -eq "$(grep -cE 'kill -0' "$LR")" ]` | **a counted pin over `bin/cc-lr`'s whole source, comments included.** Any new `kill ` spelling — even in a comment explaining why the voluntary path does not kill — reddens it | write "SIGKILL" / "terminate" in prose; keep `kill -0` the only `kill` token |
| `tests/cc-lr-front.bats` iron rule | same | also bans `it2 session send`, `osascript`, `git`, `launchctl` verbs other than bare `kickstart`. A voluntary verb must stay a **request writer**, never an actuator | design constraint, not a fix |
| `tests/lr-fleet.bats` | `:320` — `[ "$(grep -c -- '--in-place' "$LRH_LOG")" = 1 ]` | counts occurrences of `--in-place` in the args `lr-fleet.sh:801` passes. **Any flag spelled with `--in-place` as a prefix** (`--in-place-voluntary`) makes this read 2 | name the flag `--voluntary`, disjoint from `--in-place` |
| `tests/lr-drill-selftest.bats` | `:482` — `[ "$(… --rows \| grep -c .)" -eq 12 ]`, and `:432` "twelve PASS rows is the only green" | a voluntary arm added to `tests/lr-drill.sh` changes the row count | update both, in the same commit, with the plan §13 row table |
| `tests/lr-drill-selftest.bats` | `:490` RATCHET iron rule 7 — whole-file grep for `git +(commit\|push\|merge\|reset\|checkout)` in `tests/lr-drill.sh`, **including comments** | any prose in the drill mentioning a VCS verb | never write those words in that file |
| `tests/lr-drill-selftest.bats` | `:493+` RATCHET — no real-pane verb reachable outside `live_do` (`tests/lr-drill.sh:436`) | a voluntary drill arm must add a RECIPE inside `live_do`, never a call beside it | design constraint |
| `tests/test-hermeticity-lint.bats` | rule 1 `:258`, rule 2 `:415-474` | any NEW suite naming `scripts/handoff-fire.sh` must export **`HOME="$BATS_TEST_TMPDIR/home"` and `CC_FIRE_CAPACITY_GATE=off` in `setup()`** — a per-test pin does not count (`:542`); rule 7 `:1100-1115` wants `CC_ADMIT_GATE=off` for capacity-admit callers, and the two populations are deliberately disjoint | satisfy in `setup()`; do not request an allowlist entry (the ratchet only shrinks, `:266`) |
| `tests/typed-send-lint.bats` | `:300-309` — the lint's only call site, scanning the real `scripts/ hooks/ bin/` | any new raw typed-send site added to the voluntary path reddens the whole tree for the next lander | route every keystroke through the sanctioned helper |
| `scripts/pane-id-lint.sh` via `tests/pane-id-lint.bats` | whole-corpus | fixture pane ids that look like truncated pane UUIDs (8 hex/decimal digits) in new docs or tests | use short ids (`900`, `505`) as the existing suites do |
| `tests/test-walltime-lint.bats` | `:34-38` | any absolute future date in a new fixture | assemble stamps relative to a pinned `$T` |
| `tests/handoff-recycle-remote-resume.bats` | `:147` | if `:9716`'s implication becomes class-conditional, this case must keep passing for the LIMIT class — it becomes T2's twin | keep; add T2 beside it rather than editing it |
| `tests/cc-lr-front.bats` | `:159`, `:175` | the two texts a voluntary flag must not change on the bare verb | becomes T10's equivalence guard |
| `tests/handoff-fire-argv-launch.bats` | `:243,:264,:269`; `tests/handoff-fire-selfclose-refusal.bats` `:204,:206,:211`; `tests/announce-before-retire.bats` `:571`; `tests/fire-engagement.bats` `:776` | further counted pins over `scripts/handoff-fire.sh` source text | only fire if the change edits those blocks; check before landing |

**A land-gate note that is not optional:** `scripts/ship-land.sh:182-183` — *"a new `tests/*.bats` maps to itself"* — so all three new/extended suites run on the land that adds them. And the land gate runs with `CC_BATS_MAX_ROOTS=0` (`docs/lessons/the-land-gate-is-admission-exempt.md`), so do not wait on a bats admission slot before `/ship`.

---

## 7. (e) What ONLY a real end-to-end move can prove — and the safest single run

Hermetic suites cannot reach any of these, because each needs a real Claude process, a real terminal and real quota:

| Claim | Why no fixture reaches it |
|---|---|
| the `/exit` lands in the composer and the pane returns to a shell rather than closing | needs a real TUI and a real pane root process (`handoff-fire.sh`'s pane-survives predicate exists precisely because a launcher-rooted pane dies) |
| the relaunch `bash <launcher>` produces a **fresh non-error assistant turn in the TARGET's copy** | the engagement oracle is testable as a pure function (`tests/handoff-recycle-remote-resume.bats:335-370`); the *turn* is not |
| an armed `/goal` survives `--resume` on the new account | `tengu_goal_restored_on_resume` is harness behaviour |
| in-flight subagents are *actually* SIGKILLed by the process-group teardown | fixtures model the census, not the kill |
| the cache-cold re-ingest cost on the target (A10 objection 2) | needs real token accounting |
| the operator-visible window id is unchanged | needs a real window manager |

**The safest way to run it once: extend `tests/lr-drill.sh`, do not write a new script.** That file is the repo's existing answer to this exact problem and its constraints are already enforced:

- every live action goes through ONE door, `live_do` (`tests/lr-drill.sh:436-463`), whose first statement refuses unless `--drill`/`--seed` armed it — and `tests/lr-drill-selftest.bats` ratchets both that the door's armed check is first AND that no real-pane verb is spelled outside it;
- a sid is only acted on when a **provenance stamp this drill wrote for THIS run** vouches for it (`tests/lr-drill.sh:28-33`) — the guard against typing into a real working session;
- `--all` and `--drill` are mutually exclusive, refused rc 2;
- **no agent may run it** (`:13-21`); an agent exercises `--rows`, `--check-manifest`, `--verdict`, `--assert` only.

Concrete shape for this wave: one **sixth** drill session, seeded healthy (never limit-seeded), carrying **one deliberately in-flight subagent**, moved by the voluntary verb, with three new result rows — (i) the pane id is unchanged, (ii) the target's transcript takes a new assistant turn, (iii) the in-flight unit was REFUSED rather than killed. Add the `live_do` recipe inside the door; update `--rows` from 12 to 15 and the two counted assertions in `tests/lr-drill-selftest.bats` in the same commit. Run it **once**, operator-launched, on the account with the most headroom, with the box otherwise quiet.

Do NOT build an agent-runnable e2e. `docs/lessons/a-research-probe-that-drives-real-ui-writes-into-the-operator-s.md`: "read-only" is heard as "do not edit files" and does not stop an agent invoking an action whose whole purpose is to MOVE something.

---

## 8. Adversarial self-pass — three gaps found and investigated

**G1 — I nearly reported the limit predicate as the single admission gate. It is not; the SELF path is already open.** `lr-handoff.sh:805-810` states in its own comment that *"a healthy session probes `REFUSED:not-limited` and exits 5: letting that rc reach the branch above would refuse every self-recovery of a session that is merely low on context or being moved to a fresher account"* — and `tests/lr-handoff-launcher-quoting.bats:630-648` pins it as landed behaviour (commit `e508b2344`, 2026-09-22). **Consequence: a voluntary self-move is not a new capability, it is an EXISTING one with no eligibility gate at all.** That inverts the wave's risk: the test priority is not "can we admit it" but "what stops it" — which is why T11/T12/T16 rank above T7.

**G2 — the subagent auto-allow, which I would have missed by reading the recycle's test list instead of its source.** `tests/handoff-recycle-remote-resume.bats:147` asserts the auto-allow **positively** and nothing asserts the gate ever refuses on this class. Combined with G1, today's tree already permits: a healthy session with three live research subagents calls `lr-handoff --in-place`, the SELF arm records `killed_inflight=3` and proceeds, `--transplanted-source` sets `ALLOW_LIVE_SA=1`, `subagent_gate` is bypassed, and `lr-ingest-verify` clause A6 (`lr-ingest-verify.sh:226`) reports the loss **after** it happened. That is a live S1 defect independent of anything this wave ships, and T1 is its red proof.

**G3 — the background-work modal.** `handoff-fire.sh:6919-6960` auto-answers the "background work is running" dialog up to `CC_RECYCLE_BGWORK_MAX` times, choosing the KEEP row read off the screen (`hooks/lib/pane-modal.sh:263-286`). Under the limit class there is nothing running to keep. Under a voluntary move the operator's own background tasks are alive and the answer is given without them. `tests/handoff-recycle-bgwork-dialog.bats` tests the READ and never the ENTITLEMENT. T13.

**What a hostile reviewer would still say, and my answer.** *"You are designing tests for a feature A10 argues should not ship."* Correct, and the architecture is deliberately arranged so that the S1 cases (T1, T2, T3, T11, T12, T13, T16) **stand on their own merits whatever A10's ruling** — they close a hole in the forced-recovery path that exists today. The admission cases (T7-T10, T14) are the only ones contingent on the feature, and they are all two-sided.

---

## 9. Blockers and uncertainties, named

| | |
|---|---|
| **B1** | T20 is a **red on the tree today** (`LR_STATE_DIR` honoured by `bin/cc-lr` and `lr-transplant.sh:78`, hardcoded at `lr-handoff.sh:489` and `lr-reset-poller.sh:127`). Fix the writer or file it — do not land a test that ratchets a known split store. |
| **B2** | The eligibility predicate for T11/T12 assumes `lr-audit.py` exposes `lead_state` in its `--json` output. `tests/lr-audit-nonlimit.bats:319,402,444` prove the STATE exists and has a kill switch; I did not verify the exact JSON key name. Read it before writing the stub. |
| **B3** | I did not measure whether `--dry-run` reaches gate 5 (composer) — `subagent_gate` at `:9724` is proven reachable because the dry-run summary prints at `:12609`, but the composer read may sit inside the detached watcher. T13's placement (probe vs recycle) depends on that; resolve it with one `--dry-run` run against the fixture harness before committing to the suite. |
| **B4** | The flag spelling is a design decision I have constrained but not made: it must not contain `--in-place` as a substring (`tests/lr-fleet.bats:320`) and must not push `bin/cc-lr` over its iron-rule greps. `--voluntary` satisfies both. |
| **B5** | Mutation runs must execute the **whole** suite per mutant, not the single case, and must be recorded per-case in the wave report; a partial mutation pass scores cases against a possibly-decorative suite. |
