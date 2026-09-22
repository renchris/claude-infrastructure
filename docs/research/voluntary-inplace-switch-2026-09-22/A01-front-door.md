# A01 — the front door for a VOLUNTARY in-place account switch

Scope: where and in what shape a healthy, idle session gets a sanctioned route to move itself to a
better account. Read-only investigation; nothing in the repo was modified.

---

## 0. The lead's course correction: CONFIRMED, on two decisive lines

`recycle_repick()` (`scripts/handoff-fire.sh:9456-9575`) is real, and both arms shipped — the
exclusion arm and the **pressure** arm (`:9524-9569`, thresholded on the router's own
`repick_ratio=` off `--rank general`'s route-meta, never a constant authored here). It is fail-soft
in one direction only (keep the incumbent). An explicit `--account` is honoured unconditionally
(`:9738-9740`). So **fresh-context voluntary account switching is solved and must not be rebuilt.**

Two facts settle that it does NOT reach the session-preserving case:

| # | fact | anchor |
|---|---|---|
| 1 | `recycle_repick` is called ONLY inside the `elif [ -z "$LAUNCHER" ] && [ "$ACCOUNT" = "auto" ]` arm. **Resume mode takes the branch ABOVE it** — `if [ -n "$RESUME_LAUNCHER" ]; then LAUNCHER="bash"; EXPLICIT_LAUNCHER=1; ACCOUNT="(resume)"` — so on the limit-recover in-place path the re-pick is structurally unreachable, not merely skipped. | `scripts/handoff-fire.sh:9729-9733` vs `:9734-9749` |
| 2 | A plain `--recycle` **starts a new session**. handoff-fire's own header: *"the transcript … stays resumable via `--resume`"*, and the relaunch composes `launcher_for "$ACCOUNT"` with no `--resume` and no `--session-id`. The old transcript stays in the OLD account's store, so after a re-pick it is resumable only from an account the pane is no longer on. | `scripts/handoff-fire.sh:146`; `:12609` (`no goal inheritance — an unmet goal rides --resume`) |

**Therefore the gap is exactly as the lead framed it: a voluntary switch that PRESERVES the session
(same uuid, transcript transplanted into the target account's store), not one that starts fresh.**

The lead's two named residuals are confirmed and are **out of scope here**, filed as separate rows:
a Fable pane is never re-picked (`scripts/handoff-fire.sh:9474` — `case "${MODEL:-}" in
claude-fable-5*) return 0`, deliberately, pending the `--route fable` entitlement lane), and
`pre_fire_account_sweep` runs at `:9957` on the fire path only, not on the recycle pre-pass.

### Already served — do not rebuild

| use case | already served by | do NOT build |
|---|---|---|
| idle pane on an EXCLUDED account, work is disk-reconstructible | `handoff-fire.sh --recycle` (auto arm) — re-picks by itself | any "switch" verb for this |
| idle pane on a merely PRESSURED account, same | same, pressure arm `:9524-9569` | a second pressure threshold |
| operator/agent names the destination, fresh context acceptable | `handoff-fire.sh --recycle --account <A>` | a `--target` passthrough for fresh context |
| relocating recycle (new worktree + new account) | `--recycle --worktree N --account A` (`:150-157`) | anything |
| **the session's CONTEXT is the asset and must survive the move** | **nothing** — this report | ← the whole build |

---

## 1. Recommendation (decision, not a menu)

**Add `cc-lr switch` — a SELF-ONLY verb on the existing `bin/cc-lr` front end that fires
`lr-handoff.sh --launch --voluntary` in the FOREGROUND, with no `--source-pane` and no `--detach`
— and surface it to the model as a fourth mode in `commands/recover.md`. Change the engine in four
narrow places and nowhere else. Conviction 88%** (the residual is §6's two uncertainties, both of
which are verifiable by one live run and neither of which changes the shape).

The design rests on a fact that I did not expect to find and that removes most of the anticipated
work: **the session-preserving engine already admits a healthy session, deliberately, and is
tested for it.** `lr-handoff.sh`'s SELF arm ignores the probe's rc, and its own comment names this
exact use case:

> `scripts/limit-recover/lr-handoff.sh:806-810` — *"RECORD-ONLY, AND THE RC IS DELIBERATELY
> IGNORED. … In particular a healthy session probes `REFUSED:not-limited` and exits 5: letting that
> rc reach the branch above would refuse every self-recovery of a session that is merely low on
> context **or being moved to a fresher account**."*

and its control test says the same:

> `tests/lr-handoff-launcher-quoting.bats:630-651` — *"a perfectly healthy session probes
> REFUSED:not-limited and exits 5 … would refuse every self-recovery of a session being moved for
> context **or account** reasons — which is most of them."*

So **`bash ~/.claude/scripts/limit-recover/lr-handoff.sh --target <acct> --launch` from a session's
own Bash tool call already performs a session-preserving voluntary switch today, with zero code
change.** Everything below is about making that reachable, safe, and correctly routed — not about
making it possible.

Why the verb goes on `cc-lr` and not only in a command file: `cc-lr` is where the refusals and the
mutex live (`bin/cc-lr:110-158`, `:258-268`), and a voluntary switch needs a **different refusal
set** — keep RULE 0 (teammate) and RULE 1 (ambiguous), *delete* RULE 2 (not-limited), and *add*
RULE 3 (not-self ⇒ refuse). A doc-only front door gets none of those, and `commands/recover.md`'s
own precedent is explicitly a *description* widening over an unchanged engine
(`commands/recover.md:150-156`), which is the right half of the job but not all of it.

Why SELF-only and foreground, which is the opposite of `cc-lr recover`:

- `cc-lr recover` detaches (`bin/cc-lr:279`) because its subject **cannot act** — a limit-blocked
  session cannot run the command that saves it. A voluntary switch's subject **is the actor**, so
  the driver is attached by construction.
- Attached is also the only configuration measured to work. `LIMIT_RECOVER_100P.md:455-476`: the
  remote/driver in-place recycle failed **9 of 9** times from a detached or daemon driver because
  `cc-in-kitty` reads a reparented driver's ancestry as a definitive not-kitty; *"the one measured
  success (pane 695, 2026-09-09) was driven from an attached session's foreground Bash call."*
- A voluntary switch of **somebody else's** healthy session would type `/exit` into a live pane
  mid-turn. There is no busy/idle predicate in this subsystem — `pane_cc_state`
  (`scripts/handoff-fire.sh`, function body ~`:4?`; states are `cc|shell|unknown`) returns `cc` for
  a busy pane and an idle one alike, and the only idle oracle on the box is
  `bin/reso-keepalive:85-95`'s screen scrape for `esc to interrupt`, which
  `bin/cc-resume-layout.sh:24` already records as absent at narrow widths. **Refuse the case rather
  than build a width-dependent oracle.**

---

## 2. Options considered, and why each loser lost

| # | option | verdict | reason it lost |
|---|---|---|---|
| A | **`cc-lr switch`, SELF-only, foreground** | **CHOSEN** | Reuses the one already-correct engine path; adds the three refusals that path lacks; no new store, no new actuator, no flag threaded through three files. |
| B | doc-only: a `switch` mode in `commands/recover.md`, no executable change | rejected as *insufficient*, kept as *half* of A | It is the right surfacing (and A ships it too), but it gets no teammate refusal, no mutex, and no incumbent-excluding route — leaving a model to hand-compose `--target`. |
| C | `lr-handoff.sh --voluntary` alone, no front-end verb | rejected | `lr-handoff.sh` is an actuator, not a front door; `cc-lr`'s header (`:2-29`) is explicit that the composition layer is where refusals live. Also leaves the surface undiscoverable — the defect `/recover` was created to fix (`commands/recover.md:18-23`). |
| D | new `cc-lr recover --voluntary` flag on the existing verb | rejected | The verbs differ on **detach**, on **which pane is the subject**, and on **three of four refusals**. One verb with a flag that flips all of those is two verbs wearing one name; `tests/cc-lr-front.bats:91-209` pins recover's refusal set as a contract. |
| E | thread `--voluntary` down to `handoff-fire.sh --probe-recycle-preconditions` so `lr-fleet --one` admits a healthy session | rejected | This is the expensive design I started on: three files of flag-threading (cc-lr → lr-fleet → lr-handoff → probe) to unlock the **driver** path — which §1 shows is the path with a 0-for-9 record from a detached driver. The SELF path needs none of it. |
| F | widen `bin/cc-limited`'s census / `cc-find --limited` to include healthy sessions | rejected, and it is the one the code warns about by name | `bin/cc-lr:173-176`: *"The cure is NOT to widen admission: that is `bin/cc-limited`'s census contract … an OPEN OPERATOR CALL (that plan is unowned; its lead died)."* §4 shows the widening is also **unnecessary** — the census is an enumerator, never an admission gate. |
| G | reuse `handoff-fire.sh --recycle --account A` | rejected on the lead's own distinction | Fresh context. See §0 — it is the *other* feature and it already ships. |
| H | `LRH_PRECHECK=off lr-fleet.sh --one <sid> --target A --detach` (works today) | rejected as the shipped answer; named as the current workaround | `LRH_PRECHECK=off` (`lr-handoff.sh:851`) disables the **whole** precheck — losing the capacity admit + token mint (`:826-845`) and the `killed_inflight` record, which then makes `lr-ingest-verify` clause A6 refuse the fast path (`lr-ingest-verify.sh:215-226`). A blunt kill switch used as a feature. |

---

## 3. (b) The SELF-invocation path, traced — a voluntary caller reaches it UNCHANGED

Caller: the session itself, from its own Bash tool call, attached to its pane.
Command: `bash ~/.claude/scripts/limit-recover/lr-handoff.sh --target <A> --launch`

| step | anchor | what happens for a HEALTHY session |
|---|---|---|
| SID default | `lr-handoff.sh:192`, `:255` | `SID=$CLAUDE_CODE_SESSION_ID`. OK |
| in-place default fires | `:317-325` | all six negative conditions hold (`LAUNCH=1`, no `--spawn/--print-only/--no-transplant/--close-source`, `LR_INPLACE_DEFAULT≠off`) |
| **implied-pane branch (b) = SELF** | `:281-293` | `SID == $CLAUDE_CODE_SESSION_ID` **and** a terminal env var is set ⇒ `LRH_SELF_PANE` is set and **`SOURCE_PANE` stays EMPTY** — that emptiness IS the contract, pinned by `tests/lr-handoff-inplace-default.bats` |
| branch (c) DRIVER never runs | `:294-315` | (b) returns first |
| `--source-pane` registry proof | `:370-388` | **skipped entirely** — the block is gated on `-n "$SOURCE_PANE"` |
| precheck arm selection | `:757` vs `:797` | `SOURCE_PANE` empty ⇒ the **SELF arm** at `:797-822`, whose rc is discarded (`|| true` at `:814`). The limit gate is never consulted |
| recycle form | `:1039-1041` | `--recycle --transplanted-source --resume-launcher … --resume-cfg …` with **no** `--source-pane` ⇒ handoff-fire takes the self path (`:9694-9707`, `verify_self_pane`), not the remote one at `:9674-9692` |
| `--await` | `:1049-1053` | added only when `SOURCE_PANE` is set ⇒ **not** added; the caller does not block |

**Answer: yes, unchanged.** No predicate on that path asks whether the session was limited.

---

## 4. (c) Every predicate that refuses a healthy session — complete inventory

Ordered by whether the SELF path reaches it.

### 4a. Reached on the SELF path (these are the real ones)

| # | file:line | predicate | bites a voluntary switch? |
|---|---|---|---|
| S1 | `lr-handoff.sh:417-421` | `TARGET=auto` ⇒ `claude-accounts --route general`, **with no exclusion of the source account and not in the `--recovery` lane** | **YES — voluntary-specific.** For a limited session the router excludes the dead account naturally; for a healthy one it can and will return the incumbent |
| S2 | `lr-handoff.sh:426-429` | `REFUSED — target shares the source account's session store` | **YES**, as the downstream consequence of S1 |
| S3 | `lr-handoff.sh:826-834` | capacity probe ⇒ `PARKED`, exit 6 | correct and wanted; a loaded box should not take a voluntary move |
| S4 | `lr-handoff.sh:670-711` | live-layer parser + admission-token asserts ⇒ exit 5 | environment, not session class; correct |
| S5 | `lr-transplant.sh:41` / `:166-175` / `:190` / `:192` / `:202` / `:209-212` | same-store · lock names a different target · no transcript · multiple copies · dst exists · lock exists | none is limit-keyed. A repeat A→B→C switch is exempted by `SECOND_HOP` (`:127-130`), and a same-target retry returns rc 0 idempotently (`:177-184`) |
| S6 | `handoff-fire.sh:9716-9722` | `--transplanted-source` **forces `ALLOW_LIVE_SA=1`**, bypassing `subagent_gate` | **YES, and it is a SAFETY defect for this class** — see §7-A1 |
| S7 | `lr-ingest-verify.sh:162-168` (clause **A4**) | `last_api_error.kind` must be `session\|weekly\|monthly_spend` | **YES.** A healthy session has no api error ⇒ A4 FAILs ⇒ the launcher falls back to the full `/limit-recover ingest` prompt (6-9 model round trips, `lr-handoff.sh:974`). Fail-closed, so a correctness *cost*, not a break |
| — | `lr-handoff.sh:797-822` | the SELF precheck arm | **does NOT refuse** — record-only by design (`:806-810`) |
| — | `lr-handoff.sh:443-452` | dirty git tree | warns, never refuses |

### 4b. NOT reached on the SELF path (the ones that look like blockers and are not)

| # | file:line | predicate |
|---|---|---|
| N1 | `bin/cc-lr:265-268` → `cl_refuse_not_limited` (`:178-212`) | RULE 2 — the refusal in the brief. Only on `cc-lr recover` |
| N2 | `handoff-fire.sh:7833-7835` | `REFUSED:not-limited`, exit 5 — **the single limit gate in the whole engine**. Reached only through `lr-handoff.sh:757-771`, i.e. only when `SOURCE_PANE` is set |
| N3 | `bin/cc-find:150-157` (`cf_class`) + `:344` (`limited_resolve`) | a census **filter**; a named ref is classed, never refused, by cc-find itself |
| N4 | `lr-fleet.sh:229` + `:233-245` | `lf_locate`'s BLOCK_RE + last-assistant-word python — the census predicate §6a names. Enumeration only |
| N5 | `lr-fleet.sh --one`: `:1079` ambiguous · `:1109`/`:1135` already TRANSPLANTED · `:1132` no transcript | **`--one` has NO limit predicate at all** (as `bin/cc-lr:18` already states: *"a session that is not actually LIMITED is not recovered. `--one` does not check."*) |
| N6 | `bin/cc-limited` (whole file) | a census; `lr-fleet --one` consults it only when the store glob misses (`:1111-1127`) |

**Counted: exactly ONE predicate in the engine refuses a healthy session on class (N2), and the
SELF path never reaches it.** The rest of the refusal surface is front-end (N1) or enumeration
(N3-N6).

---

## 5. (d) Bypassing the census — the cost is zero, because the census is not a gate

**The voluntary path bypasses the limit census entirely, already, by construction.** The census
answers *"which sessions need recovering?"* — an enumeration problem. A voluntary caller names its
own session, so nothing needs to enumerate it. `lr-fleet --one` proves the separation is already
designed in: it is handed a sid and checks existence, ambiguity and prior-transplant, and nothing
about quota (N5).

Cost of the bypass, stated rather than hidden:

1. **A voluntary switch is invisible to `--locate` and to `cc-limited`.** It should be: a switched
   pane is not blocked and is not a husk (the pane is recycled in place, so no husk is created).
   The transplant tombstone + split-brain lock (`lr-transplant.sh:78`, `:209-233`) are still
   written, which is what `lr-fleet --duplicates` and `hf_transplant_evidence` read.
2. **`lr-ingest-verify` clause A4 has no vocabulary for the class** (S7). Fixed by §6's MANIFEST
   `reason` field — the alternative, widening A4 to accept `ABSENT`, would also pass a genuine
   crash and is refused.
3. **No new store, no new state, no widening of `bin/cc-limited`'s census contract** — which is the
   operator-owned open call `bin/cc-lr:173-176` names.

---

## 6. Per-file change list, with anchors

Re-grep every anchor before editing; line numbers are as of `8e3ab2e38`.

### 6.1 `bin/cc-lr` — the new verb (~60 lines; the only substantial addition)

| where | change |
|---|---|
| `:31-34` (header verb list) | add `cc-lr switch [--target A] [--model M] [--effort E]` |
| `:80-94` `usage()` heredoc | add the same line + one clause: *"SELF ONLY — the session that runs it is the one that moves"* |
| new `cmd_switch()`, placed after `cmd_recover` ends at `:311` | body below |
| `:542-553` argv `case` | `switch) cmd_switch "$@"; exit $? ;;` and extend `:551`'s expected-verb list |

`cmd_switch()` contract, stated so it can be implemented without re-deriving it:

1. **RULE 3 (new) — SELF ONLY.** No ref argument is accepted. `[ -n "${CLAUDE_CODE_SESSION_ID:-}" ]`
   or rc 2. A ref, if ever added, must refuse unless it equals `$CLAUDE_CODE_SESSION_ID` — the
   reason is in §1 (no idle predicate exists; `/exit` into a stranger's live turn).
2. **RULE 0 kept.** Resolve own sid through `cl_resolve` (`:214-234`) and refuse `klass = TEAMMATE`
   with `bin/cc-lr:262`'s existing text. A teammate switching itself orphans its lead's team, and
   **`lr-handoff.sh`'s SELF path has no teammate guard** (the probe's one at
   `handoff-fire.sh:7843-7846` sits behind the limit gate the SELF arm discards).
3. **RULE 1 kept**, free — `cl_resolve` already refuses ambiguity at `:219-222`.
4. **RULE 2 DELETED for this verb.** Do not call `cl_refuse_not_limited`. Do not modify that
   function — `tests/cc-lr-front.bats:175-187` pins its text byte-for-byte under
   `CC_LR_ROUTE_REFUSAL=off`. Instead, extend its routing arm (`bin/cc-lr:202-204`) to name
   `cc-lr switch` as the sibling verb for the healthy case.
5. **Mutex kept** — `cl_mutex_take "$sid" "$(cl_this_pane)"` (`:128-158`), same store, same key, so
   a switch and a recover cannot race on one sid.
6. **Fire in the FOREGROUND, no `--source-pane`, no `--detach`:**
   `bash "$LRH_BIN" --sid "$sid" --target "$target" --launch --voluntary [--model …] [--effort …]`.
   Resolve `lr-handoff.sh` on the same three-path ladder as `FLEET_BIN` (`:61-67`).
7. The iron-rule ratchet (`tests/cc-lr-front.bats:569-593`) stays green: the new code adds no
   `kill` other than `kill -0`, no `osascript`/`expect`/`it2 session send`, no git verb, no
   `launchctl` verb. Verify with the shipped positive control at `:604-625`.

### 6.2 `scripts/limit-recover/lr-handoff.sh` — three edits

| where | change |
|---|---|
| `:227` | add `VOLUNTARY=0` to the init line (**not** beside its consumer — `:230-233`'s comment records why a late init clobbers) |
| `:234-254` argv loop | `--voluntary) VOLUNTARY=1; shift ;;` |
| **`:417-429`** — the S1/S2 fix | move `SRC_REAL=…` (currently `:424`) ABOVE the routing block, then in the `auto` arm walk `claude-accounts --rank general --recovery` and **skip any candidate whose `projects/` realpath equals `$SRC_REAL`**. This is `lf_pick_target`'s own rule (`lr-fleet.sh:707-708`, *"Walk past the SOURCE account"*) and its recovery-lane argument (`lr-fleet.sh:729-735`), expressed with the realpath comparison this file already computes — so no reverse account map is needed. **Correct for the limit path too:** today an `auto` route back to the incumbent can only ever produce `:426`'s refusal, so excluding it strictly improves existing behaviour |
| `:630-644` MANIFEST | `--arg reason "$([ "$VOLUNTARY" = 1 ] && echo voluntary || echo limit)"` and `reason:$reason` in the object. This is the carrier for 6.4 |

`:797-822` (the SELF precheck arm) needs **no change** — it is already the voluntary path's home,
by its own comment and its own test.

### 6.3 `scripts/handoff-fire.sh` — one edit, and it is a safety fix

| where | change |
|---|---|
| `:9716-9722` | the implicit `ALLOW_LIVE_SA=1` must NOT fire for a voluntary switch. Add `--transplant-reason <limit\|voluntary>` (default `limit`, so every existing caller is byte-identical), passed by `lr-handoff.sh:1039`'s `RCY_ARGS` when `VOLUNTARY=1`; gate the forcing on `reason = limit`. A voluntary switch then takes `subagent_gate` (`:9723`) normally and **refuses (exit 4) with each live subagent named** rather than SIGKILLing them silently |

Why this is not optional: `:9717-9720`'s justification is *"A limit-blocked lead's subagents died
with it — their transcripts have no terminus, so the gate would read them as IN FLIGHT."* That
sentence is **true of a limit and false of a voluntary switch**, where the subagents are genuinely
running. Shipping the verb without this edit ships a silent-loss path.

**No change to `:7833-7835`.** That is the headline minimality result.

### 6.4 `scripts/limit-recover/lr-ingest-verify.sh` — one clause

| where | change |
|---|---|
| `:162-168` (clause **A4**) | read `.reason` from the manifest; `voluntary` ⇒ `clause PASS A4 "reason=voluntary" "a voluntary account switch — nothing died"`. Keep `ABSENT` and every unrecognised value FAILing, per the file's own rule at `:18-20` (*"A clause this script cannot EVALUATE is a FAILURE, never a pass"*) |

Effect: a voluntary switch whose A1/A2/A3/A5/A6 are clean (they will be — nothing was interrupted)
takes the **one-line fast path** instead of the 6-9-round-trip full ingest. Without it the feature
works and is simply expensive every time.

### 6.5 Command surface — the `/recover` precedent

| where | change |
|---|---|
| `commands/recover.md:88-135` | a fourth mode, `switch` — *"the account is fine but it is not the one worth spending; the SESSION is the asset"* — stating: SELF only · one command (`cc-lr switch`) · it recycles this pane and ends this turn · it is NOT `--recycle --account` (that is fresh context, and is correct whenever the context is disk-reconstructible) |
| `commands/recover.md:3` `description:` | add the trigger phrases: "move me to a better account", "switch accounts without losing context", "this account is the least worth spending" |
| `commands/limit-recover.md:452-511` (`Mode: handoff`) | one cross-reference line: the voluntary class has its own verb; this mode stays the limit runbook |

### 6.6 Tests

| file | add |
|---|---|
| `tests/cc-lr-front.bats` | `switch` refuses a TEAMMATE · refuses with no `$CLAUDE_CODE_SESSION_ID` · takes the mutex and fires `lr-handoff --launch --voluntary` with NO `--source-pane` and NO `--detach` · releases the mutex on a non-zero lr-handoff · the iron-rule ratchet + its positive control still pass |
| `tests/lr-handoff-inplace-default.bats` | `--voluntary` writes `reason:"voluntary"` into MANIFEST.json · `--target auto` never returns the source account (fixture: router ranks the incumbent first) |
| `tests/handoff-recycle-repick.bats` | **untouched** — assert by inspection that the new `--transplant-reason` default leaves all 25 green |
| `tests/lr-handoff-launcher-quoting.bats:630-651` | unchanged; it is already this feature's control |

### 6.7 Available today, zero code

State this in the command file as the degraded path, because it is genuinely correct:

```
bash ~/.claude/scripts/limit-recover/lr-handoff.sh --target <account> --launch
```

An explicit `--target` sidesteps S1/S2. It still carries S6 (live subagents killed silently) and
S7 (full ingest), which is exactly what 6.3 and 6.4 buy.

---

## 7. Adversarial pass — three gaps I went back and checked

**A1 — live subagents are killed silently, and the code's own reason for allowing it is false
here.** `handoff-fire.sh:9716-9722`. A limit-blocked lead's subagents are already dead; a healthy
session's are running. The probe *counts* them (`:7819-7822`) and the count is recorded
(`lr-handoff.sh:817-819`), so the loss would be *legible* — but legible is not consented. Folded
into 6.3; without it the verb is a silent-loss path on the commonest healthy-session state there
is. This is the single most important finding in the report after §0.

**A2 — does the probe refuse a session that is mid-turn?** No, and I checked rather than assumed.
`pane_cc_state` returns `cc` if **any** descendant of the pane's tty is a claude process — busy or
idle alike — so a session running the very Bash call that fired the switch still reads `cc`.
(Irrelevant on the SELF path, which never runs the probe's gates, but it would have been a blocker
for option E.) The composer read (`handoff-fire.sh:7881-7891`) correctly yields `HELD:draft` when
the operator has typed ahead — a wanted refusal, and again SELF-path-unreachable.

**A3 — does a second voluntary switch (A→B→C) deadlock on the split-brain lock?** No.
`lr-transplant.sh:127-130` sets `SECOND_HOP=1` when the lock's owner equals the store being moved
OFF, and both refusal sites (`:166`, `:209`) carry the exemption. A same-target retry short-circuits
at `:177-184` with rc 0. So the verb is safe to run repeatedly, which matters because "the account
worth spending" changes hourly.

**A4 — is there an existing backlog row or plan section for this?** No. `grep` for
`voluntary|account-switch|least-worth` across `LIMIT_RECOVER_100P.md`, `LIMIT_DETECT_100P.md`,
`bin/cc-lr` and `commands/*.md` returns nothing. The feature has never been filed; the engine
support in `lr-handoff.sh:806-810` was landed as a *side effect* of making clause A6 reachable
(2026-09-22, `e508b2344` — "a session recovering ITSELF can now record killed_inflight"), which is
why nobody has noticed it is a whole feature sitting one front door away.

---

## 8. Blockers and uncertainties, named

1. **UNCERTAIN (does not change the shape, changes the confidence): the SELF recycle has been
   measured once.** `LIMIT_RECOVER_100P.md:474-476` records one success (pane 695, 2026-09-09,
   attached foreground). Every other in-place data point is the *remote* form. Before landing, run
   the degraded path of §6.7 once on a real healthy session and read back: same pane id, same uuid,
   new config dir, a new assistant turn in the target's copy. **One live run settles it.**
2. **UNCERTAIN: `--transplant-reason` may need to reach further than `:9716`.** I traced the
   forcing site and the `subagent_gate` call; I did not audit every other consumer of
   `RCY_TRANSPLANTED_SOURCE` (`:8867`, `:8912`, `:8916`, `:9683`) for a second limit-shaped
   assumption. Grep that symbol's five sites before implementing 6.3.
3. **BLOCKER for a NON-self switch, and it is why the verb is self-only:** there is no idle/busy
   predicate in this subsystem. Building one on `esc to interrupt` inherits the measured
   geometry-dependence (`docs/lessons/screen-oracle-is-only-true-at-its-measured-geometry.md`;
   `bin/cc-resume-layout.sh:24`). If a driver-form voluntary switch is ever wanted, that predicate
   is its own decision packet — do not smuggle it in here.
4. **Out of scope, confirmed, filed to the lead:** the Fable re-pick hole
   (`handoff-fire.sh:9474`) and `pre_fire_account_sweep` being skipped on recycles (`:9957` is the
   fire path only). Both are properties of the fresh-context re-pick, not of this build.
5. **Not verified by execution.** Everything here is a code read on a clean `main` at `8e3ab2e38`.
   No command was run against the live fleet and no file was modified.
