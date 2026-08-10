# 03 · Headless substrate — the implementable spec for Wave E's two comms gaps

**Scope.** Close the two gaps `CONCURRENCY_PROGRAM.md` §S6.7-MEASURED names, so a pane-less Claude
session is a first-class fleet citizen: (1) identity/liveness is keyed on a pane id, so peers are
told a live headless session is dead; (2) nothing wakes an idle headless session.

**Code read at `origin/main` tip via `/Users/chrisren/Development/.worktrees/scale-150`** (commit
`e13910ff`). Live-layer reads under `~/.claude` are marked as such. Every claim is `file:line` or a
live read; inferences are labelled **[inferred]**.

---

## 0 · Three premise corrections the spec must be built on (all measured this session)

These change the shape of both fixes. Two of them mean the gaps are *wider* than the plan states;
one means part of gap 2 is *already built and merely unregistered*.

### C1 — the live registry is **already not keyed on a pane UUID**. It is keyed on a kitty window id.

The fleet runs kitty. `scripts/kitty-setup.sh:305` synthesises
`export ITERM_SESSION_ID="w0t0p0:$KITTY_WINDOW_ID"`, and `hooks/session-register.sh:101-104` strips
to the part after the colon and shape-checks it with `*[!0-9A-Fa-f-]*` — which **digits pass**. Live
read of `~/.claude/cc-registry/`: **38 of 38 rows are keyed on a small integer**, not a UUID:

```
paneUUID "1"   name claude-infrastructure-1   pid 3546   sid 4c3a5846-…
paneUUID "14"  name wt-890e31d89575-14        pid 15904
paneUUID "56"  name wt-b384effb4100-56        pid null   sid null   ← provisional row, handoff-fire
paneUUID "930" …
```

Consequences the spec must absorb:

- The "pane UUID" identity the plan proposes to *replace* is already a **reusable small integer**.
  kitty window ids are server-scoped and monotonic from 1; a kitty restart resets the counter, so a
  fresh window 1 lands on the retained dead row for key `1`. **[inferred from the id shape + the
  observed 1..930 span; falsifier: restart kitty and re-read the first new id.]**
- `scripts/pane-id-lint.sh:52` (`PANE_RE='(^|[^-0-9A-Za-z])[0-9A-F]{8}([^-0-9A-Za-z]|$)'`) is blind
  to these keys — the corpus lint that guards address truncation cannot see the address form the
  fleet actually uses.
- Any "make it session-keyed" change is therefore **not a downgrade in address quality**. It is a
  strict upgrade: a v4 UUID minted per session replaces a recycled per-terminal integer.

### C2 — pane-less sessions **already run on this box today**, and are already invisible to `cc-registry`.

Measured live, in this very subagent's process tree: `~/.claude/cc-beats/` holds 1,211 rows; **33
carry `pane:""`**, and two of those are provably live (pid alive AND `ps -o lstart=` matches the
recorded `lstart`):

```
sid=4c3a5846-549b-48c7-97c7-3d51ec8f8440  pid=56864  cwd=…/wt-crash-rootcause-2026-08-09
sid=e0670908-e54b-46b9-986b-7900a68f9de8  pid=56864  cwd=…/wt-crash-rootcause-2026-08-09
```

`e0670908-…` is this subagent's own session id. My own env reads
`ITERM_SESSION_ID=<UNSET> CC_PANE_ID=<UNSET>`, `ps -o tty=` gives `??`. **Subagent sessions are the
headless substrate, already, at fleet scale** — and the gap-1 failure mode is live right now, not
hypothetical. No `cc-registry` row exists for either sid; no `~/.claude/mailbox/e0670908*` box
exists.

Note the second half: **both sids share pid 56864**, because `hooks/session-beat.sh:74-81` walks to
the durable `claude` ancestor. **A pid is not unique per session.** Any registry keyed on
`kill -0 pid` for a pane-less session will report a *dead subagent* as LIVE for as long as its lead
runs. This is the single sharpest constraint on the gap-1 design (see §1.2 R3).

### C3 — the headless **wake mechanism is already written, tested, and merely UNREGISTERED**.

`hooks/mailbox-wake-arm.sh` exists (130 lines, 12 tests + 2 killed mutants per
`tests/mailbox-wake-arm.bats`) and already solves the pane-less case at `:63`:
`_key="${_pane:-$_sid}"` — pane preferred, **harness `session_id` as the fallback**, with the
rationale at `:26-36` naming exactly the resumed/pane-less failure. It translates the inverted
contract (asyncRewake wakes on exit 2; cc-await-ping exits 0 on mail) at `:109-130`.

It is **not deployed**. Live read: `grep -c asyncRewake ~/.claude/settings.json` → **0**; no
`mailbox-wake-arm` line anywhere in the live settings. The registration lives in
`migrations/0007-mailbox-wake-arm-registration.sh`, which is C10 operator-only and **has not been
run**. So gap 2's first deliverable is not "design a wake path" — it is "run 0007, then extend it".

---

## 1 · GAP 1 — identity: peers are told a live headless session is dead

### 1.1 Current mechanism — the full call-site enumeration (question a)

**The write side refuses outright.** `hooks/session-register.sh:101-104`:

```bash
pane="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; pane="${pane##*:}"
case "$pane" in ''|*[!0-9A-Fa-f-]*) return 0 ;; esac
```

A pane-less session does not get a *stale* row — it gets **no row at all**. The plan's phrasing
("keyed on a pane UUID") understates it: the failure is at registration, one layer above lookup.

**The read side then correctly reports absence as death.** `bin/cc-notify:885-917` `target_live()`
loads `~/.claude/cc-registry/*.json` directly (`:230-257`), finds no matching row, falls through to
`it2_list_bounded` (`:911`), gets a readable array without the id, and `return 1` →
`verdict mailbox-only reason=target-not-live` (`:963-964`). **A lookup-miss is converted to a death
verdict**, which is exactly the fleet-memory `lookup-miss-is-not-absence` class.

| Consumer | Line | Keys on | Headless verdict today |
|---|---|---|---|
| `hooks/session-register.sh` | `:101-104` | `CC_PANE_ID ∥ ITERM_SESSION_ID` | **no row written** |
| `hooks/session-deregister.sh` | `:42-45` | same | no-op (nothing to remove) |
| `bin/cc-sessions` | `:227-248` | `<paneUUID>.json` + `kill -0` + it2 membership | never listed |
| `bin/cc-notify` (resolve) | `:264-273`, `:280-301` | registry rows, live-only | name never resolves |
| `bin/cc-notify` (liveness) | `:885-917` | registry row → it2 list | **`mailbox-only reason=target-not-live`** |
| `bin/cc-reconcile` (self-heal) | `:131-139` argv filter, `:169-172` pane, `:196` `kind` | 3 independent exclusions | **cannot heal it** |
| `bin/cc-reaper` `live_pane_count` | `:574-578` | argv, skips `-p/--print/--version` | invisible to the truth signal |
| `bin/cc-relogin` | `:238` | same argv filter | invisible |
| `bin/cc-teardown` | `:148-149`, `:299-320` | `ITERM_SESSION_ID` scraped from `ps -E` | cannot address or verify |
| `hooks/teammate-auto-shutdown.sh` | `:351-357` | `ps eww … ^ITERM_SESSION_ID=` | cannot resolve |
| `hooks/live-session-registry.sh` | `:26-30` | `basename($cwd)` under `~/Development/.worktrees` | writes; **collides** (§4 A2) |
| `hooks/mailbox-drain.sh` | **`:75`** | `own_pane` required | **exit 0 — the hard blocker (§1.3)** |
| `bin/cc-await-ping` | `:87-90` | `CC_PANE_ID ∥ ITERM_SESSION_ID` | exit 3 with no arg |
| `bin/cc-inbox-guard` | `:159-192`, `:396` | it2 pane list for owner liveness | escalates INDETERMINATE → phone page |

**The seam that already exists and is the whole leverage: `CC_PANE_ID`.** `bin/cc-pane:67-80`
defines it as *"a SUPERSET of `$ITERM_SESSION_ID`: it accepts either the bare id or the
`wNtNpN:<id>` form"*, and 10 of the 14 rows above already read
`${CC_PANE_ID:-${ITERM_SESSION_ID:-}}`. Setting `CC_PANE_ID=<session-id>` in a headless session's
environment therefore lights up register / deregister / drain / await-ping / notify-self /
teardown-self / wait / thread / desk-register / waiting-recycle **with no code change**.

The four that are **not** covered by that seam all scrape another process's environment and must be
edited: `bin/cc-reconcile:169`, `bin/cc-teardown:316`, `hooks/teammate-auto-shutdown.sh:356`, and
(as a classification, not identity) the three argv `-p` filters.

### 1.2 Proposed identity design

**The identity already exists and is deployed: `hooks/session-beat.sh`'s row.** `:50-52` states the
principle verbatim — *"sid is the IDENTITY key, deliberately NOT the pane: tmux panes inherit the
server's ITERM_SESSION_ID, so a pane-keyed beat would have N sessions overwrite one row"* — and the
row it writes to `~/.claude/cc-beats/<sid>.json` (`:104-110`) is
`{sid, pane, cwd, pid, lstart, t, kind, who, operatorT, seq}`. It tolerates `pane:""` (33 live rows
prove it), and it carries **`lstart`** — the pid-reuse guard `cc-registry` rows lack entirely.

Design, in three rules:

- **R1 — the key is `session_id`; the pane becomes an optional attribute.** `cc-registry` rows gain
  a `sid` field they already have (`session-register.sh:171-172` writes `session_id`) and the
  *filename* becomes `<sid>.json` for pane-less sessions, `<paneUUID>.json` unchanged for pane
  sessions. Both live in one directory; every reader already iterates `*.json` and reads fields, so
  no reader needs a new enumeration. `hooks/lib/mailbox-pending.sh:118-124` `_mbx_valid_uuid`
  already accepts *any safe filename component*, so the mailbox layer needs nothing.
- **R2 — liveness is `(pid, lstart)`, never `pid` alone.** Copy `session-beat.sh:80-81`
  (`ps -o lstart= -p "$cpid" | tr -s ' ' | sed …`) and `bin/cc-pane-headless:44,55-70` `is_live()`,
  which additionally rejects **zombies** (`ps -o stat=` → `Z*`) — `kill -0` succeeds on a zombie,
  which is how `spawn -- /usr/bin/false` once returned rc 0 and a fresh id.
- **R3 — for a pane-less session, `pid` is NOT a discriminator (C2).** Two live sids share pid
  56864. So `(pid, lstart)` proves *the container is alive*, never *this session is alive*. The
  session-level liveness oracle must be the **beat freshness** (`cc-beats/<sid>.json` `.t`), read
  through `hooks/lib/cc-beat.sh` — which already ships `cb_last_beat`, `cb_operator_age` and, load-
  bearingly, **`cb_system_live`** (`:69+`), the existence gate that distinguishes *a beat-less
  session inside a live world* (suspicious) from *a beat-less world* (the producer is not deployed).
  Collapsing those two is how a fail-closed reader silently inerts an entire subsystem.

**Verdict vocabulary.** `cc-notify` must gain a fourth liveness state. Today `target_live()` returns
0/1/2 = live/not-live/unknown. Add **3 = live-but-unwakeable** (a beat-fresh, pane-less session with
no armed watcher), rendered as `verdict=delivered reason=no-watcher-headless`. This is the honest
answer the current code cannot express, and it is the one that stops a live session being retired.

### 1.3 The blocker the plan does not name — and the reason P3 PASSED anyway

`hooks/mailbox-drain.sh:73-75`:

```bash
# THE PANE IS STILL REQUIRED — it is how this hook knows WHICH container it is in…
case "$own_pane" in ''|*[!0-9A-Fa-f-]*) exit 0 ;; esac
```

A genuinely pane-less session's drain hook **exits before reading a single mailbox line**. Mail is
enqueued, the cursor never advances, and `cc-inbox-guard` eventually pages.

**So why did the precondition probe's P3 pass?** Because
`scripts/headless-precondition-probe.sh:116-124` launches `"$CLAUDE_BIN" -p … &` **with the probe's
own environment**, no `env -u`. The probe was run from a terminal session, so the child inherited
`ITERM_SESSION_ID`; `own_pane` was the *parent's* pane, `own_sid` was the probe's `--session-id`, and
`:88-92` selected the session box — which is exactly where the probe had written
(`:149 MAIL_FILE="$MAIL_DIR/$SID.md"`). **P3 measured a headless session that still carried a pane
id.** It is a true and useful result about `-p` + hooks + `additionalContext`; it is *not* evidence
that a pane-less session can receive mail. Re-run with `env -u ITERM_SESSION_ID -u CC_PANE_ID` and
P3 becomes FAIL at `mailbox-drain.sh:75`. **That re-run is the cheapest falsifier in this document
and should be step 0 of the wave.**

Second correction, same file: the plan cites `cc-notify` returning `verdict=mailbox-only` as
evidence of the liveness bug. The probe passed **`--mailbox-only`** (`:151`), and
`bin/cc-notify:872-878` short-circuits to `verdict mailbox-only reason=requested` **before**
`target_live()` runs. The verdict was *requested*, not *derived*. The underlying defect is real and
the code path is `:963` (`reason=target-not-live`) — but it was never exercised. Distinguish the two
`reason=` tokens when writing the regression test, or it will pass vacuously.

### 1.4 Exact edit list — gap 1

| # | File:line | Before → After |
|---|---|---|
| E1 | `hooks/session-register.sh:101-104` | `case "$pane" in ''\|*[!0-9A-Fa-f-]*) return 0;; esac` → on empty/invalid pane, **fall through with `pane=""`** and take `key="$sid"`; keep the refusal only when *both* pane and sid are empty. Row gains `sid` as the filename when pane is empty. |
| E2 | `hooks/session-register.sh:168-174` | row object gains `lstart` (from `ps -o lstart= -p "$CPID"`, the `session-beat.sh:81` expression verbatim) and `pane` may be `""`. Keep `paneUUID` populated for pane sessions — **no existing reader changes**. |
| E3 | `hooks/session-register.sh:151-164` | tenancy gate: when keyed on `sid`, the gate is unnecessary (a sid is not inherited) — skip the ancestor walk on that branch, saving up to 16 `ps` forks per headless start. |
| E4 | `hooks/mailbox-drain.sh:69-92` | **the load-bearing edit.** Replace the `:75` hard exit with: `own_pane` empty AND `own_sid` present ⇒ `own_uuid="$own_sid"`, skip `mailbox_alias_write` (`:81-84` — a self-alias is meaningless), skip the `:147-151` coverage fold and `:210-214` own-pane migrate (nothing to fold from). Refuse only when **both** are empty. |
| E5 | `hooks/session-deregister.sh:42-45` | mirror E1: resolve the row path as `<pane>.json` else `<sid>.json`. The proven-match gate at `:51-56` is unchanged and is *stronger* on a sid key (the key IS the proof). |
| E6 | `bin/cc-sessions:229-247` | `uuid=$(jq -r '.paneUUID // empty')` → `jq -r '.paneUUID // .sid // empty'`; add the `lstart` re-check beside `kill -0` at `:234`; for a pane-less row skip the it2-membership stale test at `:235` (a pane list can only ever *miss* it — the `lookup-miss-is-not-absence` trap, and today it would mark every headless row stale). |
| E7 | `bin/cc-notify:885-917` | `target_live()`: match `.paneUUID` **or** `.sid`; add `lstart` verification; add return code **3 = live-but-unwakeable** sourced from `cb_last_beat` freshness. `:949-961` gains the `3)` arm → `verdict delivered reason=no-watcher-headless`. |
| E8 | `bin/cc-notify:911-916` | gate the it2 fallback on `[ -n "$pane_of_row" ]` — never adjudicate a pane-less target with a pane list. |
| E9 | `bin/cc-reconcile:131-139` | the argv filter drops `-p`. Change to: drop `--version` always; drop `-p` **only when `--input-format` is absent** (a resident headless session carries `--input-format stream-json`). Classification by argv is legitimate here; **liveness stays `(pid,lstart)`** — argv never becomes the liveness oracle. |
| E10 | `bin/cc-reconcile:169-172` | no `ITERM_SESSION_ID` ⇒ currently `n_no_pane++; continue`. Change to: fall through and synthesise a **sid-keyed** row from `sessions/<pid>.json` (`.sessionId`, `.cwd`, `.startedAt`, and `.procStart` → `lstart`). Add an `n_headless` counter so the class is countable, never silent. |
| E11 | `bin/cc-reconcile:196` | `[ "$kind" = interactive ]` → accept the headless `kind` too. **Unresolved: what value CC writes for a resident `-p` session.** All 9 live rows across 5 config dirs read `kind:"interactive"`. Resolve by measurement in step 0, never by guess. |
| E12 | `bin/cc-reaper:574-578` | same argv change as E9, plus: a headless row is never a reap *target* by pane absence. `live_pane_count`'s header says it must stay in lockstep with `cc-reconcile` — change both in one diff. |
| E13 | `bin/cc-inbox-guard:159-192` | owner liveness: before returning `2` (INDETERMINATE → escalate), consult `cb_last_beat "$u"`. A fresh beat ⇒ **live**, not indeterminate. Without this, every headless box with unacked mail pages the phone (§4 A4). |
| E14 | `hooks/live-session-registry.sh:30` | `base=$(basename "$cwd")` → `base="$(basename "$cwd")-${sid:0:8}"` when a sid is present, else unchanged. Fixes the pooled-worktree collision (§4 A2). Migration: the reaper's `registry_live()` (`worktree-gc.sh:361-372`) must glob `"$base"*` for a transition window. |
| E15 | `bin/cc-teardown:316`, `hooks/teammate-auto-shutdown.sh:356` | the `ps eww` scrapers grep `^ITERM_SESSION_ID=`. Add `^CC_PANE_ID=` as a first-preference key. One-line each; without it a headless teammate cannot be torn down or verified. |

**Not edited, deliberately:** `hooks/lib/mailbox-pending.sh` (already key-agnostic at `:118-124`),
`bin/cc-await-ping` (`:87` already reads `CC_PANE_ID`), `scripts/handoff-fire.sh` (7,461 lines; it
has **no pane-less spawn mode** — every fire lands as a split, and its "headless" vocabulary at
`:92-99,862` means *the firing process has no terminal*, not *the fired session has no pane*).
Spawning headless is **out of scope for these two gaps** and belongs with `bin/cc-pane-headless`.

### 1.5 Test outline — gap 1

Suites already exist and are the right homes: `tests/cc-notify.bats`, `tests/cc-sessions-offbox.bats`
(the precedent for a *second row kind* in one lister), `tests/cc-reconcile.bats`,
`tests/mailbox-drain.bats`, `tests/mailbox-session-key.bats`, `tests/mailbox-cover-pane.bats`.

| T | Assertion | Mutation control (must go RED) |
|---|---|---|
| T1 | **The falsifier first.** `headless-precondition-probe.sh` run under `env -u ITERM_SESSION_ID -u CC_PANE_ID` ⇒ P3 **FAIL** pre-fix, **PASS** post-fix | revert E4 ⇒ T1 red |
| T2 | `session-register.sh` with pane unset + sid set writes `$CC_REGISTRY_DIR/<sid>.json` carrying `pane:""`, `sid`, `lstart` | E1 reverted ⇒ no file |
| T3 | Both empty ⇒ **no row** (the refusal survives) | E1 over-widened ⇒ junk row appears |
| T4 | `cc-sessions --json` lists the sid-keyed row; `--names` resolves it; a row whose `lstart` differs from the live pid's is **absent** from the addressing view | drop the lstart check ⇒ a recycled pid resolves |
| T5 | `cc-notify <sid> "x"` ⇒ `verdict=delivered`, **not** `mailbox-only`. Pin `reason=`, not just the verdict — `reason=requested` vs `reason=target-not-live` is the §1.3 vacuity trap | E7 reverted ⇒ `mailbox-only reason=target-not-live` |
| T6 | Beat-fresh + no `.watching` ⇒ `verdict=delivered reason=no-watcher-headless` (rc 3 arm reachable) | delete the `3)` arm ⇒ falls to `0)`, reason wrong |
| T7 | `mailbox-drain.sh prompt` with pane unset + sid set emits `additionalContext` containing the enqueued line | E4 reverted ⇒ empty output, exit 0 |
| T8 | `cc-reconcile` synthesises a sid-keyed row for a fixtured resident-headless pid (argv carries `-p --input-format stream-json`), and **still skips** a true one-shot `claude -p "hi"` | E9 over-widened ⇒ one-shot probes get rows |
| T9 | `cc-inbox-guard sweep --dry-run` classifies a beat-fresh headless box as **live**, not INDETERMINATE; a beat-stale one still escalates | E13 reverted ⇒ escalation on a live session |
| T10 | **Subagent regression (C2).** Two rows sharing one pid: killing one session's beat freshness must not mark the other dead, and `kill -0` alone must not keep the dead one alive | key liveness on pid only ⇒ T10 red both ways |

---

## 2 · GAP 2 — nothing wakes an idle headless session

### 2.1 What wakes a PANE session today

Three layers, and **only the middle one is deployed**:

1. **Model-armed watcher (deployed, and the only live path).** `bin/cc-await-ping` polls
   `mailbox_keyset(key)` every `--interval` (15s default), writes a `<key>.watching` heartbeat
   carrying its own pid, and **exits on mail**. The wake is *the watcher process exiting*: the
   harness's task-completion notification synthesises a turn. Actuated by two nags:
   `hooks/mailbox-drain.sh:250-277` (the wake nudge, hoisted above the empty-inbox exit at `:240-249`
   precisely so it fires on the "connection opened" path) and `hooks/session-continue.sh:315-460`
   (the WAKE FLOOR — a bounded Stop `decision:block` that asks the model to arm). Both advertise
   `cc-await-ping` with **no id argument** (`:259`, `:416`), so the watcher derives
   `${ITERM_SESSION_ID##*:}` itself.
2. **Keystroke injection: GONE.** `bin/cc-notify:35-38` — the v1 `it2 session send` transport was
   removed because it raced live input. There is no keystroke wake to port.
3. **Mechanical arm at birth (built, tested, NOT registered).** `hooks/mailbox-wake-arm.sh` +
   `migrations/0007-…`. See C3. This is the only path that does not require the model to cooperate.

**Fleet-wide effectiveness, as recorded in the code that fixed it:** `mailbox-drain.sh:231-234`
cites *0 armed watchers across 16 live sessions*; `session-continue.sh:319-321` cites *0 armed
watchers across 74 mailboxes holding 1,300 unacked lines*. Live read now: **135 `.watching` markers
across 248 boxes** — materially better, and consistent with the nudge+floor having landed. A
model-dependent arm is still structurally weaker than a hook-mechanical one.

### 2.2 Why every pane path fails headless, precisely

| Mechanism | Headless failure | Evidence |
|---|---|---|
| `cc-await-ping` no-arg | exits **3** — `${ITERM_SESSION_ID##*:}` is empty | `bin/cc-await-ping:87-90` |
| the drain nudge | never emitted — hook exits at `:75` before reaching `:250` | `hooks/mailbox-drain.sh:75` |
| the WAKE FLOOR | in one-shot `-p`, a Stop `decision:block` has **no stdin to continue from** → the session dies with `Error: Input must be provided…` | `CONCURRENCY_PROGRAM.md` §S6.7-MEASURED item 2 |
| `asyncRewake` wake | unregistered (C3); and its "synthesise a turn" contract is **unproven in `--input-format stream-json`** | live settings `asyncRewake` count 0 |
| task-completion notification | requires the harness to own a turn loop; in stream-json a turn boundary exists **only when something writes stdin** | §S6.7-MEASURED item 2 |

**The invariant that falls out:** in stream-json resident mode the *only* thing that can create a
turn boundary is a **write to the session's stdin**. Every wake design must terminate in that write.

### 2.3 Candidate wake mechanisms available to this fleet

| # | Mechanism | Precondition | Verdict |
|---|---|---|---|
| W1 | **Watcher writes a `{"type":"user",…}` line into the session's stdin FIFO** | the spawner owns the FIFO and publishes its path; the session runs `--input-format stream-json` | **ADOPT.** The plan already names it; it is the only one that satisfies §2.2's invariant directly. The probe proves the shape works (`headless-precondition-probe.sh:168` writes exactly such a line to fd 9 and gets a full turn). |
| W2 | `asyncRewake` SessionStart hook (`mailbox-wake-arm.sh`) | migration 0007 run; harness synthesises a turn in stream-json | **ADOPT for PANE sessions now** (free — the code is written and tested). **Unproven headless**; measure before relying on it. |
| W3 | Harness task-completion notification (today's pane wake) | an interactive turn loop | **REJECT headless** — assumes the loop stream-json does not have. |
| W4 | `claude -p --resume <sid> "<msg>"` re-invocation | a resumable transcript; a fresh process per wake | **REJECT as the primary.** Cold-starts a process per message; forks context lineage; loses the resident session's in-memory state — which is the entire point of residency. Keep as the **cold-inbox drain** for a session that has exited. |
| W5 | `tmux send-keys` into a detached tmux pane | a tmux server + a pty per pane | **REJECT.** Re-introduces one pty per session — it defeats the pty argument and re-creates the keystroke race `cc-notify:35-38` deleted. |
| W6 | launchd-triggered sweep (`WatchPaths` on `~/.claude/mailbox`) | a LaunchAgent; `WatchPaths` fires on directory mtime | **ADOPT as the backstop only.** One agent for the whole fleet, not one per session — it then *delegates* to W1 per target. Solves the herd (§4 A3) but adds latency and cannot itself deliver. |

**Chosen design: W1 primary, W6 as the fleet-level trigger, W2 for pane sessions, W4 for cold boxes.**

### 2.4 The wake design (W1) — three artefacts

**A. A published stdin endpoint.** The spawner (`bin/cc-pane-headless` `v_spawn`, `:76-146`) already
mints `hdl-<16hex>`, a 700-mode dir, `meta` with `pid`/`pstart`, and an `inbox` file. Extend `meta`
with `fifo=<path>` and `sid=<session-id>`, and spawn the agent with
`--input-format stream-json --session-id <sid> < "$fifo"`. `v_spawn:118` currently redirects
`</dev/null`; that is the one line that must change.

**B. A waker that writes a user message, not a signal.**
New `bin/cc-wake-headless <sid|id>`: resolve `meta`, verify `is_live()` (`:55-70` — pid + `pstart` +
non-zombie), then append one stream-json user line to the FIFO instructing the model to read its
inbox. Idempotent + damped: refuse a second wake within `CC_WAKE_MIN_S` (default 20s, mirroring
`mailbox-drain.sh:109`'s post-tool floor).

**C. `cc-notify` calls it.** In the new rc-3 arm (E7), after enqueue, invoke the waker. This is what
converts `verdict=delivered reason=no-watcher-headless` into `reason=woken`.

**Why not "have the headless session arm a `cc-await-ping`":** it can (E4 restores the nudge), and it
should as defence in depth — but the watcher's wake *is process exit*, and in stream-json nothing
consumes that exit. The watcher would fire correctly and change nothing. **The wake must be a write
to stdin; only the spawner can own that fd.** This is why gap 2 cannot be closed inside the hooks
alone, and why it is genuinely "a new wake mechanism on comms infrastructure".

### 2.5 Exact edit list — gap 2

| # | File:line | Before → After |
|---|---|---|
| F0 | `migrations/0007-mailbox-wake-arm-registration.sh` | **run it** (operator-only, C10). Free win for every pane session; independently valuable. |
| F1 | `bin/cc-pane-headless:118` | `( cd "$cwd" && exec "$@" ) >"$dir/out.log" 2>&1 </dev/null &` → `mkfifo "$dir/in.fifo"`; `exec 9>"$dir/in.fifo"` held by a small supervisor; agent reads `< "$dir/in.fifo"`. Use `mkfifo` + a plain background job, **never a process substitution** — `$!` after `exec 9> >(cmd)` names the wrong job (indexed fleet failure `procsub-pid-is-unreachable-own-the-pipe`, and `headless-precondition-probe.sh:105-111` already states this rule). |
| F2 | `bin/cc-pane-headless:124-131` | `meta` gains `fifo=`, `sid=`. |
| F3 | `bin/cc-pane-headless:152-158` `v_send` | today appends to `$dir/inbox` — **a private file no fleet reader knows**. Change to: write through `cc-notify --mailbox-only <sid>` (the fleet inbox), then call the waker. This is what joins the two disjoint substrates (§4 A5). |
| F4 | **new** `bin/cc-wake-headless` | as §2.4 B. ~80 lines. |
| F5 | `bin/cc-notify` (new rc-3 arm from E7) | after enqueue, `cc-wake-headless "$uuid"`; verdict `delivered reason=woken` on success, `reason=no-watcher-headless` on refusal. Never claim a wake that did not happen (`claimed-outcome-vs-checked-outcome`). |
| F6 | `hooks/session-continue.sh:349` | `wake_floor()` must **abstain** for a headless session — the abstain machinery already exists at `:385-407` (the teammate/teardown third state) and prints its reason. Add a fourth reason: *"pane-less session — its wake is the spawner's stdin write, not a watcher."* **Without this, the floor blocks a Stop that has no continuation and kills the session** (the measured `Error: Input must be provided…`). |
| F7 | `hooks/mailbox-drain.sh:259-261` | the nudge advertises no-arg `cc-await-ping`, which exits 3 headless. Advertise `cc-await-ping "$own_uuid"` when pane is empty, or suppress the nudge entirely on the headless branch — a nag for a command that cannot run is pure noise at 150× scale. |

### 2.6 Test outline — gap 2

| T | Assertion | Mutation control |
|---|---|---|
| T11 | Resident stream-json session + `cc-notify <sid> "TOKEN"` ⇒ the model echoes `TOKEN` **without any further stdin write by the test**. The un-fakeable form is the probe's own (`headless-precondition-probe.sh:160-183`): a token that exists nowhere but the inbox | F4/F5 reverted ⇒ the session sits idle and the test times out |
| T12 | Wake damping: two sends inside `CC_WAKE_MIN_S` ⇒ **one** turn | remove the damp ⇒ 2 turns (and at 150 sessions, a broadcast storm) |
| T13 | Dead agent: `cc-wake-headless` on a `pstart`-mismatched pid returns rc 1 and writes nothing | drop the `pstart` check ⇒ writes into a recycled pid's FIFO |
| T14 | Zombie agent: `spawn -- /usr/bin/false` then wake ⇒ rc 1, not rc 0 | drop the `ps -o stat= Z*` check ⇒ rc 0 (the exact `cc-pane-headless:55-70` regression) |
| T15 | **Full-FIFO safety.** A dead-but-unreaped reader ⇒ the waker must not block forever. Assert a bounded non-blocking write | unbounded write ⇒ the test hangs, and in production one wedged agent hangs its notifier |
| T16 | `wake_floor()` abstains for a pane-less session and says so on stderr; a **pane** session still blocks | F6 reverted ⇒ headless session terminates with `Error: Input must be provided` |
| T17 | Migration 0007 idempotence + `asyncRewake:true` present exactly once | already covered — `tests/mailbox-wake-arm-migration.bats:31-56` |

---

## 3 · Coverage table across session shapes

Post-fix behaviour. **kitty pane** is the shape the fleet actually runs (C1).

| Property | kitty pane | iTerm2 pane | tmux pane | headless `claude -p` resident | headless one-shot `-p` | resumed (`--resume`) | subagent (C2) |
|---|---|---|---|---|---|---|---|
| `ITERM_SESSION_ID` | synthetic `w0t0p0:<winid>` (`kitty-setup.sh:305`) | real UUID | **inherited from the server — N sessions, one value** (`session-beat.sh:51`) | unset (or inherited — the probe's flaw, §1.3) | unset | **may be lost across the resume** (`mailbox-wake-arm.sh:27-30`) | unset (measured) |
| registry key today | integer, reusable | UUID | **collides across panes** | none | none | none | none |
| registry key post-fix | integer (unchanged) | UUID (unchanged) | `<sid>` — collision gone | `<sid>` | none (correct — E9 keeps the exclusion) | `<sid>` | `<sid>` |
| liveness oracle | `(pid,lstart)` + it2 | `(pid,lstart)` + it2 | `(pid,lstart)` | `(pid,lstart)` + **beat freshness** (R3) | n/a | `(pid,lstart)` | **beat freshness only** — pid is shared |
| receives peer mail | yes | yes | yes (one box per sid post-fix) | **yes, after E4** | no (dies first) | yes | **yes, after E4** — new capability |
| wake path | watcher exit → task notification; +W2 after F0 | same | same | **W1 stdin write** | n/a | W2 (session-id fallback, `mailbox-wake-arm.sh:63`) | W3 today; W1 if spawner-owned |
| reaper sees it | yes | yes | yes | **after E9/E12** | excluded (correct) | yes | no — not a reap target |
| `cc-teardown` can close it | yes | yes | partially (`ps -E` scrape) | **after E15** | n/a | yes | no |

---

## 4 · Adversarial pass — what a hostile reviewer raises

**A1 — "Stale pid reuse: you're replacing a pane id with a pid."** Half-right, and the mitigation is
already in-tree twice: `bin/cc-pane-headless:44,55-70` (`pstart` + zombie discrimination) and
`hooks/session-beat.sh:80-81` (`lstart`, with the comment *"identity is (pid,lstart), never pid
alone: a RECYCLED pid must not masquerade"*). **`cc-registry` rows carry neither today** — so pid
reuse is a hazard the *current* pane-keyed registry already has and the fix removes (E2/E6). The
residual, and it is the sharp one, is **A1′**: for a pane-less session pid is not even unique (C2 —
two live sids on pid 56864), so `(pid,lstart)` proves container-liveness, not session-liveness. R3
answers it with beat freshness. A design that skips R3 will report every ended subagent as live for
the lead's whole lifetime.

**A2 — "cwd collisions."** Real and already latent. `hooks/live-session-registry.sh:30`
(`base=$(basename "$cwd")`) is a **per-worktree** key; the tenancy gate at `:73-96` refuses only when
the incumbent pid is a live *ancestor*. Two headless sessions pooled on one worktree are siblings,
not ancestors, so the second silently overwrites the first's row, and `worktree-gc.sh:361-372`
`registry_live()` then falls back to the flaky cwd/lsof oracle this file exists to eliminate — i.e.
**a live worktree becomes reapable.** E14 fixes it. Note the current fleet already runs pooled
worktrees (`wt-pool-*` is explicitly excluded by `session-register.sh:264`), so this is not
speculative.

**A3 — "Wake thundering herd."** Two distinct storms, both measurable:
- *Poll cost, O(N²).* `mailbox_keyset` (`hooks/lib/mailbox-pending.sh:598-620`) takes a **reverse
  edge** — `grep -lF " $k" ~/.claude/mailbox/.alias/*` — whenever the key has no forward alias. A
  **session-keyed** watcher takes that branch **every poll**. Live read: `.alias` holds **1,276
  files / 5.0 MB**. At 150 headless sessions polling every 15s that is ~10 greps/sec over 5 MB
  (~50 MB/s of re-read) plus a 1,276-argument argv per call — a plausible `E2BIG`/`ARG_MAX` wall as
  the trail grows. **Mitigation:** W1 removes the need for a per-session watcher entirely (the wake
  is a push, not a poll); if watchers are kept as defence-in-depth, cache the reverse edge or index
  it, and never let 150 pollers scan one growing directory.
- *Delivery burst.* A fleet broadcast wakes 150 sessions at once — 150 concurrent model turns
  against the very inference budget §S6.8 says does not exist. **Mitigation:** damp per target (T12)
  and stagger in the sender; `cc-announce` is the natural chokepoint.

**A4 — "You'll storm the operator's phone."** `bin/cc-inbox-guard:396` escalates a box whose owner
liveness is INDETERMINATE, and `:159-192` derives that from `it2 session list` — which can only ever
*miss* a headless session. So without E13, **every headless box with unacked mail pages the phone.**
This exact failure has already happened here: `bin/cc-comms-alarm-sweep:12` records *"cc-inbox-guard
paged the operator once per fixture record (510 pages…)"*. E13 is not optional hardening; it is a
precondition for turning the substrate on.

**A5 — "There are two headless designs and they don't talk."** `bin/cc-pane-headless` (landed
2026-07-31, `1f7be212`; `TERMINAL_AGNOSTIC_L3_L4.md` P2) has its own id namespace (`hdl-<16hex>`),
its own registry (`~/.claude/autonomy/panes/<id>/meta`), and its own inbox
(`v_send:152-158` appends to `$dir/inbox`) — **which no fleet reader knows about**. Its own plan says
so at L3/L4 `:137-139`: *"nothing yet drains a headless inbox … headless is addressable but not yet
load-bearing."* Meanwhile S6 Phase E assumes the fleet mailbox. **Decide once, in this spec:** F3
routes `cc-pane-headless send` through `cc-notify --mailbox-only <sid>` so there is ONE inbox. Two
inboxes is how a message becomes unfindable.

**A6 — "The `-p` classifier is argv-keyed, and this fleet's own memory says argv is not liveness."**
Correct, and the split is deliberate: argv (`--input-format stream-json`) is used **only to
classify** *is this a resident session or a one-shot?*; **liveness is never argv** — it stays
`(pid,lstart)` + beat freshness. State that in the E9 comment or the next reader will "fix" it
wrongly. Better still: prefer a **declared marker** — the spawner's `meta` file — over argv, and use
argv only for sessions the spawner did not create.

**A7 — "The precondition you're building on was measured with a pane id in the environment."** §1.3.
This is the one finding that could invalidate the wave's premise, and it costs one command to
settle. It is step 0.

**A8 — "You are adding a fourth `verdict=` token to a contract callers grep."**
`bin/cc-notify:100-108` names the token set, and `cc-announce`, `scripts/completion-push.sh` and
`scripts/desk-invariant.sh` all grep the prose. `reason=` is the safe extension point (already
free-form: `wake-path-armed`, `no-watcher`, `target-not-live`, `requested`); a **new `verdict=`
value would land in every consumer's `*)` fail-closed arm** — the indexed
`new-enum-member-falls-into-fail-closed-default` failure. **Extend `reason=`, never `verdict=`.**

---

## 5 · Sequencing, and what "done" means

0. **Falsify the precondition** — re-run the probe under `env -u ITERM_SESSION_ID -u CC_PANE_ID`
   (§1.3, A7). Also record what `kind` CC writes to `sessions/<pid>.json` for a resident `-p`
   session (E11 depends on it) and whether the file is written at all.
1. **Run migration 0007** (F0) — free, independent, already tested.
2. **Gap 1, identity** — E1-E8 (hooks + listers + notify) as one diff; E9-E15 (scanners, guard,
   scrapers) as a second. E4 and E13 are the two that must not ship separately from the rest.
3. **Gap 2, wake** — F1-F7, gated on step 0 and on step 2's E4.
4. Only then is `handoff-fire.sh` a candidate for a pane-less spawn mode. It is not on this path.

**Done = T1 flips FAIL→PASS**, plus T5/T7/T11/T16 green with their mutation controls RED. Anything
less leaves the substrate addressable but deaf — which is exactly where `TERMINAL_AGNOSTIC_L3_L4.md`
already left it eight days ago.

### Open questions this spec could not close by reading

- **Q1** `kind` for a resident `-p` session (E11). All 9 live rows read `interactive`. Measure.
- **Q2** Does `asyncRewake` synthesise a turn in `--input-format stream-json`? W2's headless value
  hinges on it. Unproven either way.
- **Q3** kitty window-id reuse after a server restart (C1). **[inferred]** — one restart settles it.
- **Q4** `bin/cc-inbox-guard` has no hook or LaunchAgent wiring that a grep over `settings.json` and
  `~/Library/LaunchAgents/*.plist` could find. If it is genuinely un-invoked, A4's severity drops —
  and a *different* problem (the fail-loud backstop is inert) is the finding.
