# H5 — the context-ceiling husk: cure shape, admissible class, fleet census

**Read-only analysis. No repo file was edited. Every proposal below is diff-shaped TEXT, applied nowhere.**
Worktree: `/Users/chrisren/Development/.worktrees/ctx-ceiling-postmortem`. All measurements 2026-09-22, 06:2x–06:4xZ.

---

## ANSWER FIRST

1. **Add a SEPARATE rung, do not widen `limited` — conviction 88 %.** Widening on `error` is refuted by a measured counterexample in our own store: the only `invalid_request` death on this box (`19d0c318`, 2026-09-21T02:16:51Z) is an Opus 5 **AUP/safeguards** refusal — identical `error` string, opposite terminality — and `limited` is the **admission token of the transplant lane**, which a context death must never enter (there is nothing to move; the context is full on every account).
2. **The new class is the SIXTH, not the fifth** (`handoff-fire.sh:8284` already names the automatic fired-peer-stamp recovery "THE FIFTH ADMISSIBLE CLASS"). Required legs, all unforgeable-by-the-model: **L1** transcript's last assistant record is `isApiErrorMessage ∧ error=invalid_request ∧ "Prompt is too long"` ∧ **L2** no `type=="assistant"` record after L1's ts in ANY copy ∧ **L3** a live registry row whose pid holds that sid ∧ **L5** the terminal enumerates pane P ∧ **(c)** no recovery in flight ∧ **(d)** not a teammate; telemetry `used_pct` and `cc-beats` corroborate only. It takes `--terminal` and **forbids `--successor`** — the exact inversion of SAME-ACCOUNT SUPERSESSION, which exists to prove something IS carrying the session.
3. **Census: context = 7 events / 5 sessions / 30 d; quota = 22 sessions by last-death `rate_limit`, but over a ≤7-day store, not 30** (the producer GCs marker files at `-mmin +10080`). The two populations are **disjoint — 0 overlap**, and `cc-limited` sees **0 of 5** context deaths. Live registry today: **12 live rows** (not 9), **1 context husk** (pane 500), **0 quota husks**.

---

## 0. What the subject actually is — the four reproduced refusals

| # | claim | label | receipt |
|---|---|---|---|
| 0.1 | the death record is `invalid_request`, classed `other` by the repo's own SSOT predicate | **MEASURED** | `. scripts/limit-recover/lr-lib.sh; lr_last_api_error <tx>` → `5ae08419-e12e-4d49-96ad-b76898189d8a<TAB>invalid_request<TAB>other<TAB>2026-09-22T06:15:51.646Z` (rc 0) |
| 0.2 | the recycle probe refuses `not-limited` | **MEASURED** | `bash scripts/handoff-fire.sh --probe-recycle-preconditions --source-pane 500 --source-session 397428c4-…` → `registry: ok pane=500 session=397428c4` / `limit: NO — the last assistant record is other (…)` / `verdict: REFUSED:not-limited` |
| 0.3 | the pane is classed `SESSION`, so `cc-lr recover` refuses before it starts | **MEASURED** | `cc-find 500` → `397428c4-…<TAB>500<TAB>claude-tertiary<TAB>…<TAB>LIVE<TAB>SESSION`; the refusal is `bin/cc-lr:214` `[ "$klass" != LIMITED ] → exit 2` (quoted in §1.1) |
| 0.4 | it is **not** a W10 HUSK either — no lock, no tombstone | **MEASURED** | `lr_husk_state 397428c4-… /Users/chrisren/.claude-tertiary` → rc **1**; `lr_transplant_target …` → rc **1** |
| 0.5 | pid alive, idle, started 30 min BEFORE the death and still up 46 min AFTER it | **MEASURED** | `ps -o pid,lstart,etime -p 99367` → `Tue 22 Sep 00:45:57 2026 / 46:11`; death 06:15:51Z; clock at read `2026-09-22T06:32:08Z` |
| 0.6 | fill at death 97.3 % of a 1 000 000 window | **MEASURED** | `/tmp/cc-telemetry/397428c4-….json` → `{"window":1000000,"used_pct":97,"input_tokens":972773,"pid":99367,"pane":"500"}`; `cc-ctx-audit` peak row `972773 / 1000000 / 97.3` |

### 0.7 METHOD WARNING — the transcript keeps GROWING after the death

`tail -3` of the subject's transcript returns `{"type":"permission-mode"}`, `{"type":"atis-latch"}`, `{"type":"bridge-session"}` — harness metadata records written *after* 06:15:51Z. **MEASURED.**
⇒ Any "did it take another turn" leg must be scoped to `type=="assistant"` with a real `message.content`. A file-grew / mtime / size test reads a context husk as ALIVE, forever. (`lr_last_api_error` is already correct here — it filters `d.get("type") != "assistant"` and skips `"No response requested."`.)

---

## 1. WIDEN `limited` vs. a SEPARATE rung — **separate rung, conviction 88 %**

### 1.1 The two front doors, quoted verbatim

`bin/cc-lr:214-217` (the `klass` comes from `cc-find`, which renders `SESSION` for the subject):
```sh
  if [ "$klass" != LIMITED ]; then
    echo "cc-lr: REFUSED — ${sid:0:8} (pane ${pane}) is class ${klass:-UNKNOWN}, not LIMITED: its last assistant word is not a usage-limit error, so there is nothing to recover. No mutex was created and nothing was started." >&2
    exit 2
  fi
```

`scripts/handoff-fire.sh:7818-7822`, inside `--probe-recycle-preconditions` step 2 (its own header: *"WAS IT A LIMIT? A network death has a retry ladder that may still be running (93-101 min measured), and a clean session is not owed a recovery at all"*):
```sh
  PRP_ERR="$(lr_last_api_error "$PRP_TX" 2>/dev/null || true)"
  PRP_KIND="$(printf '%s' "$PRP_ERR" | cut -f3)"
  if [ "$PRP_KIND" != limit ]; then
    echo "limit: NO — the last assistant record is ${PRP_KIND:-not an api error} ($PRP_TX)"
    prp_verdict "REFUSED:not-limited" 5
  fi
```
Both test the **same field**: field 3 of `lr_last_api_error`, whose vocabulary is **binary** — `scripts/limit-recover/lr-lib.sh:222-225` sets `kind = "limit" if classify_text(...)["limit"] else "other"`. **MEASURED** by reading the function body.

### 1.2 The api-error taxonomy that actually exists on this box

`scripts/limit-recover/lr_predicate.py` (the SSOT, its own docstring) defines three tiers and **two nulls**:

- **T0 envelope** — `type=="assistant" ∧ isApiErrorMessage`. Failing it ⇒ `kind is None` = **ABSENCE**.
- **T1 structure** — `error=="rate_limit" ⟺ apiErrorStatus==429`, *"measured 490/490 in BOTH directions … of the 348 api-error records that carry no status at all (transport failures), ZERO are limits."*
- **T2 text** — sub-kind only, never membership.
- `kind=="other"` = *"it IS an api error whose class this module does not recognize. A VERDICT."*

So the module already distinguishes ABSENCE from UNRECOGNISED. What it does **not** have is a **terminality** axis. Observed `error` values, from the live store (**MEASURED**, `~/.claude/autonomy/stop-failure/*.jsonl`, 78 rows / 40 sids):

| `error` | rows | sessions (by LAST death) | terminal for the pane? |
|---|---|---|---|
| `rate_limit` | 52 | 22 | **no** — clears at reset, or transplants |
| `server_error` | 18 | 10 | **no** — transient; the probe's own comment cites a 93–101 min retry ladder |
| `authentication_failed` | 7 | 7 | **no** — clears on `/login` (the login-cliff path) |
| `invalid_request` | 1 | 1 | **it depends on the TEXT** — see 1.3 |

### 1.3 🚨 The measured counterexample that kills "widen on any terminal api-error"

The **only** `invalid_request` record in the store is not a context wall:

```
sid 19d0c318  ts 2026-09-21T02:16:51Z  pane 403  cwd /Users/chrisren/Development/personal
 last: API Error: Opus 5's safeguards flagged this message (https://www.anthropic.com/legal/aup). Our intentionally broad safeguards allow us to deliver more capabilit…
```
**MEASURED.** Same `error` string as the context wall. **Not terminal** — that pane can take another turn with different content. `cc-limited --since 30d --tsv` renders it `other / other`.

⇒ `error` alone cannot carry terminality. Only `error ∧ text` can. Anything widened on the structured field alone would classify an AUP refusal as a dead pane and retire a live one.

### 1.4 The decisive argument: `limited` is a LANE TOKEN, not a description

`kind=="limit"` is consumed by four things, and each one is **wrong** for a context death:

| consumer | what it does on `limit` | on a context death |
|---|---|---|
| `handoff-fire.sh --probe-recycle-preconditions` (W2) | admits the transplant | ✗ transplanting reproduces the wall on turn 1 — the context is full on every account |
| `bin/cc-lr recover` → `lr-fleet.sh --one … --detach` | takes the mutex, drives a recovery | ✗ spends a transplant on a pane nothing can revive |
| `lr-reset-poller.sh` | parks on `resets_at` until the cap clears | ✗ `classify_text` gives a context death no `resets_at` and `recoverable_by_waiting=False` ⇒ parks **forever** |
| `hooks/stop-failure-marker.sh` ARM 2 (`case "$ERR" in rate_limit|rate_limit_error)`) | writes a recovery REQUEST for the poller to drain | ✗ mints a request no driver can satisfy |

**This is exactly the repo's own shape** — `docs/lessons/a-ratchet-cures-one-verb-of-a-two-verb-class.md`. §6a named the generator correctly (*"the predicate answers did this session last turn die at a limit; the operator question is CAN THIS PANE DO WORK. A husk is precisely where those diverge"*) and then cured **one verb** — RECOVER. The second verb, **RETIRE**, re-emits the same generator here. The cure is not to make `limited` mean "cannot do work"; it is to put a second disposition on the same census axis, which is precisely what W10 already did for the transplant husk.

### 1.5 The two options, priced

| | **(A) WIDEN `limited` → "any terminal api-error"** | **(B) SEPARATE rung `context` beside `limited`** ← RECOMMENDED |
|---|---|---|
| fixes | one predicate change unblocks both front doors at once | both front doors, with the right verb behind each |
| breaks — false positives | `server_error` (18 rows, 10 sessions) and `authentication_failed` (7) are non-terminal; the AUP `invalid_request` is non-terminal. A widened `limited` sweeps **35 of 78 rows** into the transplant lane | none measured. The predicate is strictly narrower than today's `other` bucket |
| breaks — cc-limited census contract | `--assert-clean` and `--reaper` fold on `limit`; widening changes what "blocked" means for a consumer that already renders 4 kinds → **operator fork per backlog `3d9943ec9e87`** | **none** — a new value on an axis that already carries `auth_cliff / network / other / limit`; see §4 for the one place it still reaches |
| poller | non-reset kinds enter a park with no `resets_at` and never leave | `recoverable_by_waiting=False` routes to retire, never to park |
| waves amended | **W2** `handoff-fire.sh` `--probe-recycle-preconditions` (`:7818`); **LIMIT_DETECT_100P W0** `lr_predicate.py::classify_text` + `lr-lib.sh:174 lr_last_api_error` (SIBLING PLAN, single owner, unowned) | **W10** `lr-lib.sh::lr_husk_state` + `lr-fleet.sh:186 lf_locate` (a second husk sub-kind); **W2** the probe's kind branch; **W12** one drill arm; **NOT** the predicate SSOT |

**Recommendation: (B).** Conviction **88 %**. What the residue is, stated plainly: the remaining 12 % is not a missing fact — it is a **shape preference** the operator may hold, namely whether one verb (`cc-lr recover <ref>`) should dispatch on sub-kind internally rather than the caller choosing `recover` vs `retire`. That is a UX call, not a measurement, and (B) does not foreclose it (`cc-lr` can branch on the rung and call the right driver).

### 1.6 PROPOSAL — diff-shaped, NOT APPLIED

```diff
--- a/scripts/limit-recover/lr-lib.sh
+++ b/scripts/limit-recover/lr-lib.sh
@@ (new function, beside lr_husk_state)
+# ── CONTEXT HUSK — a live pane whose session hit the HARD context refusal ────────────────────────
+# The THIRD husk shape. cc-husk-sweep models a bare shell over a dead session; lr_husk_state models
+# a live process whose session MOVED. This one is a live process whose session CANNOT MOVE: the
+# window is full, so every account reproduces the wall on turn 1 and there is nothing to transplant.
+#
+# 🚨 IT IS NOT A LIMIT AND MUST NEVER BE CLASSED ONE. `limit` is the transplant lane's admission
+# token (probe :7818, cc-lr :214, the poller's park, the marker hook's request arm). The remedy here
+# is RETIRE, so the rung has to be its own — docs/lessons/a-ratchet-cures-one-verb-of-a-two-verb-class.md.
+#
+# 🚨 THE TEXT IS THE DISCRIMINATOR, NOT `error`. Measured 2026-09-22: the only invalid_request in
+# ~/.claude/autonomy/stop-failure is an Opus 5 AUP/safeguards refusal (19d0c318) — same error string,
+# and that pane can take another turn. Keying on the structured field alone retires a live session.
+lr_context_dead() { # $1=transcript → rc 0 when the LAST assistant record is the hard context refusal
+  local tx="${1:-}" line err txt
+  [ -n "$tx" ] && [ -f "$tx" ] || return 1
+  line="$(lr_last_api_error "$tx" 2>/dev/null)" || return 1
+  err="$(printf '%s' "$line" | cut -f2)"
+  [ "$err" = invalid_request ] || return 1
+  # the text arm — one bounded tail read, the same LR_TAIL_BYTES bound lr_last_api_error uses
+  lr_last_api_error_text "$tx" 2>/dev/null | grep -q 'Prompt is too long' || return 1
+  return 0
+}
```

```diff
--- a/scripts/handoff-fire.sh
+++ b/scripts/handoff-fire.sh
@@ -7818,7 +7818,15 @@ (inside --probe-recycle-preconditions, step 2)
   if [ "$PRP_KIND" != limit ]; then
+    # A CONTEXT DEATH IS A DIFFERENT VERDICT, NOT A LOUDER REFUSAL. Today this prints
+    # REFUSED:not-limited and rc 5 for a pane that will never produce another turn, which sends the
+    # operator to a recovery that cannot exist. Name the state; the remedy is retire, not recycle.
+    if lr_context_dead "$PRP_TX" 2>/dev/null; then
+      echo "limit: NO — CONTEXT CEILING at $(printf '%s' "$PRP_ERR" | cut -f4). This pane cannot execute another turn and there is nothing to transplant (the window is full on every account)."
+      prp_verdict "REFUSED:context-dead" 6
+    fi
     echo "limit: NO — the last assistant record is ${PRP_KIND:-not an api error} ($PRP_TX)"
     prp_verdict "REFUSED:not-limited" 5
   fi
```
*(rc 6 rather than 5 deliberately: `docs/lessons/` — `new-enum-member-falls-into-fail-closed-default`. A caller spelling `case 5)` keeps its meaning; a caller that has not learned the new state falls into its `*)` arm and refuses, which is the safe direction.)*

---

## 2. The SIXTH admissible self-close class — `--context-dead`

### 2.1 Numbering correction (**MEASURED**)

The brief calls `--transplanted-source` the fourth and asks for a fifth. `scripts/handoff-fire.sh:8284` already reads:
> `# THE FIFTH ADMISSIBLE CLASS, and the one the other four imply.` (the automatic recovery of a fired peer whose `mark_fired_peer` never ran)

⇒ The proposal below is the **SIXTH**. Getting this wrong matters because `SC_ORIGIN_CLASS` is a **single derivation** read by the adoption step and both refusal branches — the file's own comment at `:8192` warns that *"a class added at one site and missed at another is the correctly-placed-wrongly-narrow failure, and it fails SILENTLY."*

### 2.2 Why no existing class reaches it

| class | its oracle | why a same-account context death misses |
|---|---|---|
| fired peer (stamp) | `~/.claude/cc-fired/<pane>.json` | an operator-launched origin session has none |
| `--orphaned-assignee` | the pane IS an Agent-Team assignee + a dead originator | pane 500 is neither |
| `--transplanted-source` | tombstone + `handed_off_to ≠ this cfg` + live split-brain lock | **MEASURED rc 1**: no tombstone, no lock. And `hf_transplant_evidence:2290` refuses with *"No tombstone means no completed transplant, so this pane is not a husk — it is an ORIGIN session, and it stays up. This flag names a CATEGORY; it cannot confer one."* |
| SAME-ACCOUNT SUPERSESSION (`:2308-2335`) | tombstone naming THIS cfg + `superseded_by_pid` alive | no tombstone at all, and **no successor pid exists by construction** |
| auto stamp-recovery (`:8284`) | handoff-fire composed this brief | the session was operator-launched |

### 2.3 Evidence legs

**UNFORGEABLE BY THE MODEL** — each is written by the CLI, the kernel or the terminal, and no agent can author it:

| leg | what it asserts | source | required? | receipt for the subject |
|---|---|---|---|---|
| **L1** | last assistant record is `isApiErrorMessage ∧ error=="invalid_request" ∧ text contains "Prompt is too long"`, with its uuid + ts | the CLI writes the transcript record | **ALL** | `5ae08419-… / invalid_request / other / 2026-09-22T06:15:51.646Z` |
| **L2** | **no** `type=="assistant"` record with real content after L1's ts, in **ANY** copy of the transcript (union over `$CC_PROJECTS_DIRS`, `.handed-off` twins, salvage copies) | the CLI; the union rule is `cc-limited:686` `row["blocked"] = not (last_turn and last_turn > death.ts)` | **ALL** | one copy on disk (tertiary); `lr_last_api_error` returns the error record as LAST ⇒ holds |
| **L3** | a **live** registry row whose `session_id` == S and whose `pid` answers `kill -0`, on THIS account | `hooks/session-register.sh` + the kernel | **ALL** | `~/.claude/cc-registry/500.json` → pid 99367 alive, acct `claude-tertiary`, `startedAt 1790055958000` |
| **L5** | the terminal **enumerates** pane P (a live kitty socket lists window P, or an iTerm2 UUID resolves) | `kitty @ ls` / the it2 API — the same read W8's `hf_remote_pane_term` does | **ALL** | `cc-where` lists `win 500` under kitty window 79 / tab 86 |
| **(c)** | **no recovery in flight** for S: no live `__recycle` watcher naming pane P or sid S, and no `handoffs.jsonl` row younger than `LR_HUSK_MIN_AGE_S` (900 s) | `ps -axo command=` with both needles **in the ENVIRONMENT** | **ALL** | lifted verbatim from `lr_husk_state` legs (c1)/(c2); §10.3 critic item 4 is why it is not optional |
| **(d)** | not a teammate — `head -c 8000 "$tx" \| grep '"agentName"'` is empty | the harness writes `agentName` | **ALL** | the probe already does this at step 3 |
| **(e)** | L1's ts is older than `LR_CTX_HUSK_MIN_AGE_S` (default 900 s) | the clock | **ALL** | 16 min at read time — holds |

**MODEL-AUTHORED or DERIVED — corroborating only, never required:**

| leg | why it cannot be required |
|---|---|
| `/tmp/cc-telemetry/<sid>.json` `used_pct ≥ 95` + `window` | **EPHEMERAL.** Wiped on reboot; global CLAUDE.md records coverage falling to ~0.2 % of sessions after one reboot, and the `window` cannot be imputed from the model id (one model id ran at both 200 k and 1 M in this fleet). Requiring it makes the class unreachable after any reboot. **MEASURED present today**: `used_pct 97, window 1000000`. |
| `~/.claude/cc-beats/<sid>.json` | A context-killed turn writes no turn-end beat (the `226b73888` finding: *"a limit-killed turn never writes its turn-end beat"*), so a STALE beat is consistent but not probative, and its ABSENCE proves nothing — `docs/lessons/freshness-is-relative-to-the-subject-not-the-clock.md`. |
| the `cc-lr status` / audit prose "lead process: IDLE" | derived; at best it restates L2 ∧ L3, and it is prose a model can echo — `memory: narrated-verdict-is-indistinguishable-from-a-computed-one`. |
| a close message, a plan line, a peer report | model-authored by definition. |

**Kill switch:** `CC_CONTEXT_HUSK_CLOSE=0`, matching `CC_TRANSPLANT_SOURCE_CLOSE` / `CC_ORPHAN_ASSIGNEE_CLOSE`.

### 2.4 How it differs from SAME-ACCOUNT SUPERSESSION — a structural inversion, not a tuning

`handoff-fire.sh:2308-2335` replaces the split-brain-lock requirement with a **live `superseded_by_pid`**, and its own comment states the polarity:
> *"The class then holds iff that process is alive: something IS carrying the session, on this very account… A dead successor is the plain same-dir refusal below — nothing else carries it, so closing here would retire it outright."*

Every existing husk class asserts **the work survives the close**. `--transplanted-source` enforces this mechanically at precondition (2) — `handoff-fire.sh:8171-8177` REFUSES `--terminal` and DEMANDS `--successor`.

A context death inverts that: **nothing carries it and nothing can.** So the new class:
- **MUST take `--terminal`** and **MUST REFUSE `--successor`** (the mirror of (2));
- proves not "a successor is alive" but "**no successor is possible**" — L1 ∧ L2 say this pane will never produce another turn, and the *reason* (a full window) is account-independent, which is what makes a transplant pointless rather than merely unavailable;
- therefore has **no `--successor-assume-engaged` question to answer at all**, which removes the one gate the transplanted-source path leans hardest on — and that is exactly why the legs above are conjunctive and unforgeable: the class has nothing else holding it up.

### 2.5 Cost of a false positive, and what bounds it

**The cost is closing a pane mid-work** — the failure the origin gate exists to prevent, and there is no undo: the scrollback and any uncommitted judgment die with the pane.

Bounds, in order of strength:
1. **L2 is the guard.** If the session ever takes one more assistant turn, the class evaporates. Self-close already re-verifies at the close instant (`:6482`), so the window between decision and act is closed.
2. **L2 must be `type=="assistant"`-scoped** — see §0.7. A file-grew test is defeated by the harness metadata records that keep landing.
3. **(e) the age floor** stops a retire seconds after a wall hit, before the operator has seen it.
4. **Residual, stated rather than hidden:** a session rescued at the wall would be a false positive. The global CLAUDE.md's own measurement bounds it near zero — *"7 sessions, 10 events, and compaction saved none of them (6 of the 7 had zero compactions)"* — but the class must never assume it, which is what makes re-verification at the close instant load-bearing rather than belt-and-braces.
5. **Polarity:** every leg missing falls THROUGH to the origin gate, which refuses exactly as it does today. Nothing here weakens it — the same standard `:8137` holds `--transplanted-source` to.

### 2.6 PROPOSAL — diff-shaped, NOT APPLIED

```diff
--- a/scripts/handoff-fire.sh
+++ b/scripts/handoff-fire.sh
@@ (after the TRANSPLANTED-SOURCE block, ~:8195, BEFORE the SC_ORIGIN_CLASS derivation)
+  # ---- CONTEXT-DEAD PATH — the SIXTH admissible class ---------------------------------------------
+  # THE CATEGORY. A session hits the hard context refusal ("Prompt is too long", error
+  # invalid_request). The harness does not auto-compact and nothing rescues it: every later turn
+  # returns the same error. The process stays ALIVE and IDLE, so the pane looks like live work.
+  #
+  # WHY IT IS NOT ANY OF THE FIVE. There is no fired-peer stamp (operator-launched), no assignee
+  # relationship, no transplant tombstone and no split-brain lock (a same-account context death
+  # produces neither), and no superseding pid — nothing is carrying this session and nothing CAN.
+  #
+  # 🚨 IT INVERTS --transplanted-source's PRECONDITION (2). That class refuses --terminal and demands
+  # --successor because its whole justification is that the work is being carried. Here the
+  # justification is the opposite and the flags must be too: --terminal REQUIRED, --successor
+  # REFUSED. A "successor" for a context death would be a new session, not a continuation, and
+  # accepting one would let a caller launder an ordinary origin close through this class.
+  #
+  # 🚨 THE TEXT IS THE MEMBERSHIP TEST, NOT `error`. Measured 2026-09-22: the only invalid_request
+  # record in ~/.claude/autonomy/stop-failure is an AUP/safeguards refusal (19d0c318) whose pane can
+  # take another turn. Keying on the structured field alone retires a live session.
+  #
+  # ADMISSIBLE ONLY WITH ALL SEVEN — each is evidence the flag cannot manufacture:
+  #   (0) CC_CONTEXT_HUSK_CLOSE=0 disables the path entirely.
+  #   (1) --context-dead names the category; the checks establish it.
+  #   (2) --terminal REQUIRED and --successor REFUSED (the inversion above).
+  #   (3) L1: the last assistant record carries isApiErrorMessage, error invalid_request, and the
+  #       literal context-refusal text. lr_context_dead owns this predicate.
+  #   (4) L2: NO type=="assistant" record after L1's ts in ANY copy under $CC_PROJECTS_DIRS. A
+  #       file-size or mtime test is NOT this check — harness metadata records keep landing after
+  #       the death (measured: permission-mode / atis-latch / bridge-session).
+  #   (5) L3 ∧ L5: a live registry row holds the sid on THIS account, and the terminal enumerates
+  #       the pane (hf_remote_pane_term, W8).
+  #   (6) no recovery in flight (lr_husk_state legs c1/c2) and not a teammate (agentName in the
+  #       first 8 KB), and L1's ts is older than LR_CTX_HUSK_MIN_AGE_S (900 s).
+  if [ "$SC_CONTEXT_DEAD" = 1 ] && [ "${CC_CONTEXT_HUSK_CLOSE:-1}" != 0 ]; then
+    [ -z "$SC_ORIGIN_CLASS" ] || { echo "!! self-close REFUSED: --context-dead names a DIFFERENT class than $SC_ORIGIN_CLASS; pass one." >&2; exit 2; }
+    if [ "$SC_TERMINAL" != 1 ] || [ -n "$SC_SUCCESSOR" ]; then
+      { echo "!! self-close REFUSED: --context-dead needs --terminal, and never --successor."
+        echo "!!   The class asserts this pane can never execute another turn AND that nothing is"
+        echo "!!   carrying its session — the window is full, so no account can. A successor would be"
+        echo "!!   a NEW session, not a continuation; naming one would launder an origin close."
+      } >&2; exit 2
+    fi
+    hf_context_dead_evidence "$SC_TS_SID" "$CC_PROJECTS_DIRS" self-close || exit 2
+    SC_ORIGIN_CLASS="context-dead"
+    echo "→ context-dead close AUTHORIZED: session ${SC_TS_SID:0:8} died at the context ceiling ($HF_CD_TS); no assistant turn since, pid $HF_CD_PID alive and idle, pane $SC_SID enumerated" >&2
+    echo "→ nothing survives this close because nothing can: the transcript is retained on disk and is the only artifact" >&2
+  fi
```

---

## 3. Fleet census — 30 days

### 3.1 Context-ceiling deaths — **MEASURED**

Instrument: `cc-ctx-audit --wall-hits --since 30d` (the lead's run; read from `…/tasks/bwwc7s1er.output`, complete, rc 0).

```
wall hits (hard context refusal)   since=30d : 7 event(s) in 5 session(s)
    08c8a975  2026-09-11T22:02:23.299Z  /Users/chrisren/Development/mac-bootstrap
    9fc1946f  2026-09-13T21:16:58.908Z  /Users/chrisren/Development/claude-infrastructure
    f0947ae8  2026-09-14T04:14:28.281Z  /Users/chrisren/Development/.worktrees/wt-cc-202600-2515
    f0947ae8  2026-09-14T04:14:47.369Z  /Users/chrisren/Development/.worktrees/wt-cc-202600-2515
    4101dbdf  2026-09-14T15:38:07.256Z  /Users/chrisren/Development/chris-capital-group-contributions/ocr-prompts
    4101dbdf  2026-09-14T15:39:02.787Z  /Users/chrisren/Development/chris-capital-group-contributions/ocr-prompts
    397428c4  2026-09-22T06:15:51.646Z  /Users/chrisren/Development/.worktrees/cf-reso-actions
```
Events > sessions because `f0947ae8` and `4101dbdf` each hit the wall **twice, 19 s and 55 s apart** — the signature of the terminal state (every later turn returns the same error).

### 3.2 Quota deaths — instrument, and what it cannot see

Instruments used: **`cc-limited --since 30d --tsv`** (13 rows) and the raw store it reads, **`~/.claude/autonomy/stop-failure/*.jsonl`** (10 files / 78 rows / 40 distinct sids). Both **MEASURED**.

`cc-limited --since 30d --tsv` kind column: `auth_cliff 7 · limit 3 · network 2 · other 1`.
Raw store, by each session's **LAST** death error: `rate_limit 22 · server_error 10 · authentication_failed 7 · invalid_request 1`.

**🚨 Three blind spots, all measured — do not quote the 30 d figure without them:**

1. **The window is ≤ 7 days, not 30.** The producer GCs whole marker files at `find "$MARKER_DIR" -name '*.jsonl' -mmin "+$TTL_MIN" -delete` with `TTL_MIN=10080` (`hooks/stop-failure-marker.sh:80`). Oldest surviving row: **2026-09-17T09:19:25Z** — 5 days. So `--since 30d` is a filter over a store that structurally cannot hold 30 days. **The true 30-day quota denominator is UNKNOWN and strictly ≥ 22 sessions.** The context figure (§3.1) is a genuine 30-day scan of transcripts; the quota figure is not. *They are not directly comparable, and the honest statement is a rate: quota ≥ 22 sessions / ≤ 7 d (≥ 3.1/day) vs context 5 sessions / 30 d (≈ 0.17/day).*
2. **It cannot see a context death at all.** `cc-limited --sid 397428c4 --tsv` → **0 rows**; `cc-limited --all --tsv` → 13 rows, **none is it**. Root cause, and this is a NEW finding beyond backlog `3d9943ec9e87`: **cc-limited's POPULATION is the marker store**, not transcripts (`cc-limited:204` `enumerate_deaths()` walks `MARKER_DIR`). **0 of 5** wall-hit sids have any marker row. The hook is live and armed: `StopFailure` is registered in **all five** config dirs (`jq '[.hooks.StopFailure[]?.hooks[]?.command]|length'` → 1 each), the live copy is byte-identical to trunk (`diff -q` → IDENTICAL), and it wrote a row at **2026-09-22T01:01:45Z**, 5 h before the subject died. Its only write gate is `[ -n "$ERR" ] || _sf_abstain "no-error-field"` — **no error-kind filter**. ⇒ **INFERRED** (not measured): either the harness does not emit `StopFailure` on the hard context refusal, or it emits one with an empty `.error`. **I could not discriminate**: the hook's `log_idl` records are absent from `~/.claude/autonomy/idl.jsonl` entirely (`grep -c 'stop-failure'` → **0**, against 78 marker rows), so the one-armed instrument that would separate "fired and abstained" from "never fired" is itself dead here — `docs/lessons/one-armed-adjudication-only-convicts.md`. The discriminating probe (not run, it would need a real wall hit or a synthetic StopFailure payload) is in §5.
3. **`invalid_request` is not a context discriminator** — §1.3.

**The two populations are DISJOINT: 0 overlap** between the 5 wall-hit sids and the 40 marker sids. **MEASURED.**

### 3.3 Live registry today — **MEASURED**, and it differs from the lead's figure

`~/.claude/cc-registry` — 22 row files, **12 live** (pid answers `kill -0`), 10 with dead pids:

```
pane 405 pid 28619 claude-secondary  2b1d0989     pane 500 pid 99367 claude-tertiary  397428c4  ← context husk
pane 480 pid 49851 claude-tertiary   2825e1e5     pane 502 pid  7776 claude-quaternary 17f965aa
pane 495 pid 18679 claude-tertiary   696eb098     pane 503 pid 75578 claude-tertiary  b6125384
pane 505 pid 49280 claude-tertiary   7c8201f8     pane 506 pid 68062 claude-tertiary  03f2392b
pane 507 pid 92220 claude-tertiary   f8dd7ab6     pane 508 pid 73296 claude-secondary 717e5f3a
pane 509 pid 33143 claude-tertiary   03d94c51     pane 510 pid 63426 claude-tertiary  4055151e
```

| | count | basis |
|---|---|---|
| live registry rows | **12** | `kill -0` on each row's pid |
| **context husks** | **1** — pane 500 / `397428c4` / claude-tertiary | the only live row whose sid carries a terminal api-error with no later assistant turn |
| **quota / auth / server husks** | **0** | cross-join of the 12 live sids against the 40 marker sids → **0 hits** |

⚠️ **The lead's "9 live rows" is not what the registry reads today**, and the difference is this postmortem's own team: panes **507** (lead `f8dd7ab6`), **509** and **510** (general-purpose agents; `510` is this agent) plus **505** did not exist at the lead's read. Neither figure is wrong — the registry is a live population and `cc-where` renders 12 panes across 4 kitty windows. The **1 context husk / 0 quota husks** halves reproduce exactly.

---

## 4. Does the recommendation require editing `cc-limited`?

**Split answer, and the split is the finding.**

**(a) The RETIREMENT path — NO cc-limited edit, and no operator fork.** Entirely inside LIMIT_RECOVER_100P's own files:

| file | change |
|---|---|
| `scripts/limit-recover/lr-lib.sh` | `lr_context_dead` + `lr_context_husk_state` (leg (c) lifted verbatim from `lr_husk_state`) — §1.6 |
| `scripts/handoff-fire.sh` | the SIXTH class + `hf_context_dead_evidence` + the probe's `REFUSED:context-dead` branch at `:7818` — §2.6 |
| `scripts/limit-recover/lr-fleet.sh` | `lf_locate` emits `CONTEXT-HUSK`; `--retire-husks` accepts the new sub-kind and fires `self-close --context-dead --terminal --source-pane P --source-session S` |
| `bin/cc-lr` | `:214`'s refusal gains a branch naming the right verb instead of "not LIMITED" |
| `tests/` | `handoff-selfclose-context-dead.bats` (new), + cases in `lr-lib.bats` / `lr-fleet.bats`; W12 drill arm (h) |

**(b) The DETECTION / VISIBILITY path — this is where it reaches an owned file, and the owner is NOT `cc-limited`.**

Backlog `3d9943ec9e87` says *"teach cc-limited's render_tsv the HUSK disposition (it already reads the registry + markers)"* — true of the W10 transplant husk, whose sids DO have markers. **It is false for the context husk**, because the session is **absent from the population**, not merely unrendered. Rendering cannot show a row that enumeration never produced. Fixing it at that layer means editing **`hooks/stop-failure-marker.sh`** or its upstream (the harness's `StopFailure` emission) — a strictly bigger fork than the one that row describes, and one that would need §5's probe first.

**(c) The escape hatch that avoids BOTH — RECOMMENDED.** `lf_locate` unions a transcript-derived arm scoped to the **live registry rows only** — today **12**, not 2 591 transcripts. That is 12 `lr_last_api_error` forks, well inside the census budget the `cc-limited` docstring is defending (35.5 s over 2 591 transcripts is the cost it exists to avoid; 12 is ~0.15 s). It keeps every change inside LIMIT_RECOVER_100P's files, needs **no** operator fork, and is the same registry × live-pid pass W10 already added:

```diff
--- a/scripts/limit-recover/lr-fleet.sh
+++ b/scripts/limit-recover/lr-fleet.sh
@@ (lf_locate, in the W10 pane-first pass — the SAME loop, one more disposition)
     # W10 asks: has this sid MOVED? (lock/tombstone naming another store)
     if lr_husk_state "$sid" "$cfg"; then disp=HUSK
+    # NEW: has this sid DIED AT THE WALL? Same population — the live registry rows, already
+    # enumerated above — so the marginal cost is one lr_last_api_error per LIVE row (12 today),
+    # never a scan of the 2,591 transcripts cc-limited's census budget is defending.
+    elif lr_context_husk_state "$sid" "$cfg"; then disp=CONTEXT-HUSK
     fi
```
**Do NOT route this through `cc-limited`'s `--since` window either** — §3.2 blind spot 1: that store's own GC caps it at 7 days, so a context husk older than the TTL would be invisible even after a render fix. The registry-scoped arm has no such window: a live row is a live row.

---

## 5. The one probe this analysis could not run

**Question:** does the harness emit `StopFailure` at the hard context refusal, and if so with what `.error`?
**Why it matters:** it decides whether (b) above is a one-line change to a hook (add the missing field / stop abstaining) or a vendor-side gap needing the §4(c) workaround permanently.
**Why not run:** it needs either a real wall hit (destroys a session) or a synthetic `StopFailure` payload piped into the hook — a write, outside this job's read-only bound.
**The command, for whoever does it** (bounded, hermetic — writes only under a scratch `STOP_FAILURE_MARKER_DIR`):
```
printf '%s' '{"session_id":"probe-ctx","cwd":"/tmp","hook_event_name":"StopFailure","error":"invalid_request","last_assistant_message":"Prompt is too long"}' \
  | STOP_FAILURE_MARKER_DIR=/tmp/sfprobe bash hooks/stop-failure-marker.sh; ls -la /tmp/sfprobe
```
A row in `/tmp/sfprobe/invalid_request__*.jsonl` proves the hook would carry it ⇒ the gap is upstream (the harness never fires, or fires with no `.error`), and §4(c) is the permanent answer. No row ⇒ the hook is the culprit and is cheap to fix.
**Second, independent gap worth filing:** `~/.claude/autonomy/idl.jsonl` carries **0** `stop-failure` records against **78** marker rows — so the hook's own liveness/abstain log is not landing, and the surface that would have answered this question in one grep is dark. That is a distinct defect from anything in this postmortem.

---

## 6. Relation to the two existing backlog rows (not duplicated)

- **`3d9943ec9e87`** (cc-limited has no HUSK disposition; conviction 80): **stands, and is narrower than it knows.** Its receipt is the W10 *transplant* husk, whose sids DO carry markers, so "teach `render_tsv`" is the right fix there. For the **context** husk the same remedy is inert — the population, not the render, is what excludes it (§3.2 blind spot 2). Worth an `update` appending that distinction rather than a new row.
- **`dbb994e2878e`** (3 quota husks self-close still cannot retire): **disjoint.** Those three have tombstones and successors and fail at the successor pane↔tty binding (W9b's subject). The context husk fails one layer earlier — at `hf_transplant_evidence`, for having no tombstone at all — and needs a class, not a gate fix.
