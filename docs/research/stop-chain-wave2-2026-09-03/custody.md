# a9ede190ee3b — custody attribution split: drivability audit

Repo: `/Users/chrisren/Development/claude-infrastructure` · HEAD = `24c598bac` = `origin/main` (verified, no drift).
Read-only. Nothing edited.

**VERDICT (detail below): DRIVABLE-NOW.** No genuine operator decision. The crux question (what to do
with an unattributable row) is *already answered on trunk* by a landed precedent + an explicit written
POLARITY rule in `bin/cc-custody`'s own header — it is determined by evidence, not by operator value.

---

## 1. The claim VERIFIED at today's origin/main — TRUE, all four sites unchanged

| # | Site | Line(s) at 24c598bac | Attribution model |
|---|---|---|---|
| 1 | `scripts/wrap-ledger.sh` `count_open_custody()` | body **772–786**, key comment **767–770**, call **1256**, rung **1257–1261**, machine emit **1367–1368**, `--full` render **1441–1447** | **cwd-only, UNattributed** — `"$bin" count --open --cwd "$PWD"` (**:782**), sets `CUSTODY_SRC="cwd"` (**:785**) |
| 2 | `hooks/operator-readout.sh` | **815, 817, 822** (block 798–822) | consumes ledger field `CUSTODY_OPEN` via `lf` — inherits model 1 |
| 3 | `hooks/completion-assert.sh` | **549–550** (header 545–548) | consumes `CUSTODY_OPEN` via `lfield`; `>0 ⇒ contra=1` — inherits model 1 |
| 4 | `hooks/session-continue.sh` wake floor | **542–577**, messages **684 / 687** | **pane-attributed, RE-DERIVED** — `cc-custody list --open --cwd "$cwd" --json` + jq on `originatorPane`/`notifyBack` (**559–565**) |

Line numbers differ slightly from the 2026-09-02 audit (it said ~772-781 / ~499-500 / ~548-575);
the *code* is identical in substance. Nothing has landed since that changes the split.

Consequence claimed — **structurally true**: `wrap-ledger.sh:782` counts every open row against the
cwd regardless of who fired it; `completion-assert.sh:550` turns any non-zero into `contra=1`; and
`operator-readout.sh:815-822` renders it. Meanwhile `session-continue.sh:613` states the opposite
contract in its own comment: *"A row a sibling in this shared checkout fired is not in `$cust` at
all, so it can no longer re-fire this floor over a session with nothing open."*

**Caveat on liveness (matters for how you frame the fix, not for whether it is real):** the defect is
currently **LATENT in this repo**. `./bin/cc-custody count --open --cwd "$PWD"` returns **0** right now
(cwd key `6cfca083a29d5a1910e2f48da299cb24`). So no close is being blocked today; the split is a
by-construction bug awaiting the next multi-session wave in the shared checkout.

---

## 2. `bin/cc-custody` — the identity fields, and whether attribution is always resolvable

Row schema (`bin/cc-custody:16`, emitted by `_row()` at **86–96**):

```
{ts, kind:open|return|abandon, cwd, originatorPane, targetPane, marker, slug, notifyBack, why}
```

Every field except `ts`/`kind`/`cwd` is **conditionally present** — `_row()` omits any empty one
(`:90-95`). There is **no session id field at all**; `cwd`, `originatorPane` and `notifyBack` are the
only identity carriers. `targetPane` identifies the *peer*, not the originator.

### Producers, and what each guarantees

| Producer | Site | `originatorPane` | `notifyBack` | Attributable? |
|---|---|---|---|---|
| `scripts/handoff-fire.sh` (`_hf_custody open`) | **10523–10526**, guard **10523**: `[ -n "$NB_ARMED_TARGET" ] && [ -n "$SPAWNED_PANE" ]` | `--originator-pane "${FIRING_SID:-}"` — **can be empty** (`FIRING_SID` set at **8916** from `$SESSION_ID`/`$ITERM_SESSION_ID`) | `--notify-back "$NB_ARMED_TARGET"` — **always non-empty by the guard** | **ALWAYS** (notifyBack guarantees it) |
| `bin/cc-offload up` (cloud fires) | **561–566** | `${ITERM_SESSION_ID:+--originator-pane …}` — **omitted entirely** when unset | `${UP_NOTIFY_BACK:+--notify-back …}` — **omitted entirely** on an unmanaged fire | **NO — can carry neither field** |

`cc-offload:584` names that state out loud: `UNMANAGED: custody OPEN but NOTHING will be woken —
collect it yourself.`

### The unattributable class is REAL and MEASURED, not hypothetical

Live store `~/.claude/autonomy/custody/` (27 files), open set derived with the same
`_OPEN_JQ` grouping `bin/cc-custody:100-104` uses:

```
open rows store-wide : 441
  has originatorPane :   0
  has notifyBack     : 324
  NEITHER field      : 117   (26.5%)
```

All 441 live in one bucket, `8a5edab282632443219e051e4ade2d1d.jsonl`, whose every row carries
`cwd: "/"` and `targetPane: "cloud:session_…"` — i.e. **cc-offload cloud fires made from a context
with no `ITERM_SESSION_ID` and PWD=/**. 117 of them carry neither identity field.

This repo's own key (`6cfca083…`) is the healthy case: every open row there carries **both**
`originatorPane` and `notifyBack` (e.g. `{"op":"102","nb":"claude-infrastructure-102"}`), which is
exactly what `handoff-fire.sh:10525-10526` guarantees.

Also note the known regression that makes this permanent: memory `resumed-session-loses-terminal-identity`
— a resumed session has no `$ITERM_SESSION_ID` (rc 3) and its pane is renumbered. So both
"row written with no pane id" and "reader has no pane id to match against" occur in production.

**Answer to Q2: attribution is NOT always resolvable.** Two independent failure modes:
(a) the ROW carries neither field (cc-offload unmanaged fire — 117 live instances);
(b) the READER has no pane identity (resumed session), which `session-continue.sh:554` already
handles by falling back to the cwd count (**:570-576**) with hedged wording.

---

## 3. THE CRUX — what happens to an unattributable row, and is the choice a VALUE decision?

### The three options and their effects

Let `mine` = rows this pane owns, `unk` = rows attributable to nobody, `theirs` = rows a sibling owns.
Today `count_open_custody()` returns `mine + unk + theirs`.

| Option | `CUSTODY_OPEN` becomes | ✅ certificate (`operator-readout.sh:~1254`) | 🔧 rung (`wrap-ledger.sh:1257-1261`) | Failure direction |
|---|---|---|---|---|
| **A. COUNT the unknown** (`mine + unk`) | drops `theirs` only | unreachable while your own or an unowned wave is open | fires on `mine` + `unk` | **over-counts** — a bounded, latched false 🔧 on an unowned row. Never silent loss. |
| **B. DROP the unknown** (`mine` only) | drops `theirs` + `unk` | reachable over an unowned open wave | silent on `unk` | **under-counts** — 117 live rows become invisible; recreates the exact wave-abandonment generator the ledger exists to catch |
| **C. COUNT SEPARATELY** (emit `mine`, `unk`, `theirs` as distinct fields) | ledger gains 2 new fields; rung must still pick one number | depends on which number the rung reads — the decision is not avoided, only relocated | same | punts; still needs A-or-B for the rung |

### It is DETERMINED BY EVIDENCE, not a value call — for three independent reasons

**(i) The repo already wrote the rule down, as a standing invariant.** `bin/cc-custody:35-38`:

> *POLARITY: cwd-keyed v1 — … over-counting a sibling's dispatch costs a bounded, latched block,
> while a per-pane key would silently DROP custody across the measured resume-loses-pane-id case.
> Chosen deliberately.*

and `bin/cc-custody:44-46` restates it for the TTL question:

> *NOT expiry. A TTL that DROPS a row is the silent-loss direction this file's POLARITY note already
> rejects … an age-triggered delete makes it invisible again, this time by construction.*

Option B is exactly the rejected direction. That is a landed, argued, invariant — not an open question.

**(ii) The identical decision has ALREADY been made and landed, in the fourth consumer.**
`session-continue.sh:537-541` decides this verbatim:

> *WHAT IS DELIBERATELY \*NOT\* DROPPED: a row carrying NEITHER field cannot be attributed either way,
> and cc-custody's own header (POLARITY, v1) rejects the direction that silently DROPS custody — a
> per-pane key loses it across the measured resume-loses-pane-id case. So an unattributable row still
> counts, and the message HEDGES instead of asserting originatorship. Same when this session has no
> pane id at all: no discriminator ⇒ the old cwd count, hedged.*

Its implementation is Option A + Option C's *wording* (not its arithmetic): the jq at **559-565**
returns `[mine, unknown]`, `cust = mine + unk` (**:569**) drives the fire predicate (**:615**), and the
two counts pick between two *different messages* (**684** vs **687**) — one asserting originatorship,
one hedging. `theirs` is dropped; `unk` is kept.

So the remedy is not "decide a policy", it is **"port the landed policy into `count_open_custody()`"** —
which is literally what the backlog title asks for: *"move the pane-attributed predicate into
count_open_custody() so all four share one oracle."*

**(iii) The failure-direction rule that governs it is also already resident** —
`lookup-miss-is-not-absence` (memory), cited by `cc-custody:58-59` for the ageHours case: *"an unknown
age must fail toward keeping the debt."* Same shape, same answer.

**Recommended shape (evidence-determined, no new policy):** make `count_open_custody()` emit
`CUSTODY_OPEN = mine + unk` (Option A), plus `CUSTODY_MINE` / `CUSTODY_UNK` as separate machine fields
so `operator-readout.sh` can hedge its wording the way `session-continue.sh:684/687` already does, and
keep `CUSTODY_SRC` as the three-state oracle (`pane` / `cwd` = no discriminator, hedged / `none` /
`error`). Best factoring: lift the jq predicate out of `session-continue.sh:559-565` into a shared
lib (or into `cc-custody` itself as a `--mine <pane>` selector) so there is genuinely ONE oracle rather
than two copies of the same jq — the "two-oracles-over-one-population" defect is named at
`completion-assert.sh:157`.

---

## 4. Consumers of `CUSTODY_OPEN` — the FULL census (repo-wide grep of scripts/ hooks/ bin/ tests/)

**Consumers of the ledger field `CUSTODY_OPEN` — exactly 3, all listed in the item:**

| File | Line | Use |
|---|---|---|
| `scripts/wrap-ledger.sh` | 1367 (emit), 1257, 1261, 1442 | producer + own rung + `--full` render |
| `hooks/operator-readout.sh` | 815 (`lf CUSTODY_OPEN`), 817, 822 | 🔧 cause string |
| `hooks/completion-assert.sh` | 549 (`lfield CUSTODY_OPEN`), 550 | `contra=1 ⇒ decision:block` |

**No fourth consumer of the FIELD exists.** `bin/cc-custody:32-34` lists exactly these three plus the
wake floor, and that list is accurate.

**Other code that touches the custody STORE (not the field) — these are the real blast radius:**

| File | Role | Attribution model |
|---|---|---|
| `hooks/session-continue.sh` | wake floor (consumer) | **pane-attributed** (the divergent one) |
| `scripts/handoff-fire.sh` | producer (`_hf_custody`, :3188-3196, :10524) + discharger (`:6943`) | writes both fields |
| `bin/cc-offload` | producer (:561-566) + discharge path | fields conditional — source of the 117 |
| `hooks/mailbox-drain.sh` | discharger on HANDOFF-PING, slug-keyed (:518) | n/a |
| `scripts/cloud-return.sh` | discharger / keeps custody open on refused land | n/a |
| `scripts/custody-deathwatch.sh` | independent watcher over the store | own model |
| `scripts/compressor-sentinel.sh`, `scripts/autonomy-sweep.sh`, `scripts/cloud-reconcile.sh`, `scripts/cloud-refusal-route.sh`, `scripts/cloud-inbox.py` | store readers / sweepers | own models |

None of these read `CUSTODY_OPEN`, so a change confined to `count_open_custody()` + the two field
consumers does not touch them. **But `scripts/custody-deathwatch.sh` is a fifth oracle over the same
population** and worth a glance for consistency if you want one attribution model repo-wide.

---

## 5. Tests over custody today — and whether a change breaks them

### The full test surface

| File | Scope | Count |
|---|---|---|
| `tests/cc-custody.bats` | the store/CLI itself — open/return/abandon, cwd normalisation, stale class, malformed args | 15 tests (`:19`–`:153`) |
| `tests/wrap-ledger.bats:1745-1790` | `count_open_custody()` → `RUNG`/`CUSTODY_OPEN`/`CUSTODY_SRC` | 3 tests (`:1761`, `:1772`, `:1782`) |
| `tests/completion-assert.bats:1139-1148` | done-claim over open custody ⇒ FIRE | 1 test (+ `:1387-1402` uses custody 0 as the terminal case) |
| `tests/operator-readout.bats:1308-1400` | the 🔧 custody cause string, incl. a pinned-sha RED-PROOF | 5 tests (`:1342`, `:1355`, `:1365`, `:1374`, `:1389`) |
| `tests/wake-floor.bats:544-598` | **the pane-attributed model** — the precedent | 5 tests |
| `tests/notify-back.bats:209`, `tests/cc-dispatch-venue.bats:301`, `tests/cc-offload.bats:550`, `tests/cloud-return.bats:378`, `tests/mailbox-drain.bats:434`, `tests/custody-deathwatch.bats` | producers/dischargers | untouched by this change |

### WOULD A CHANGE BREAK THEM? Yes — 3 tests, mechanically, and the break is EXPECTED

`tests/wrap-ledger.bats` stubs `cc-custody` with `_cust_stub` (**:1755-1759**), whose bodies are
**argument-blind one-liners**: `'echo 2'` (**:1763**), `'echo 0'` (**:1774**), `'exit 3'` (**:1784**).
They answer the same way to *any* argv. So the moment `count_open_custody()` stops calling
`count --open --cwd` and starts calling `list --open --cwd --json`:

- `echo 2` returns the literal `2`, which is not a JSON array → the new parse fails → `CUSTODY_SRC=error`
  → **`:1767-1768` fails** (expects `CUSTODY_OPEN=2` / `SRC=cwd`) and `:1769` fails (no 🔧).
- `echo 0` likewise → `SRC=error` instead of `cwd` → **`:1779` fails**.
- `exit 3` still yields `SRC=error` → **`:1782` still passes** (fail-OPEN preserved).

`tests/completion-assert.bats:1142` uses the same argument-blind `echo 2` stub → **would also break.**

`tests/operator-readout.bats` is **safe**: it stubs the *ledger* (`stub_ledger "🔧" "CUSTODY_OPEN=2"`,
`:1344`), not `cc-custody`, so it only cares that the field still exists. Its `:1365` test already
pins "a ledger with NO `CUSTODY_OPEN` field at all is a clean zero" — so adding fields is safe there.

`tests/wake-floor.bats` is **untouched** (the arm is not being changed, only copied).

**The fix is mechanical and in-session:** replace the three `_cust_stub` one-liners with the
`cust_shim` pattern that `tests/wake-floor.bats:526-541` already ships — a shim where
`list … --json` replays a JSON array and `count` answers `jq 'length'` **from that same array**, so
"a shim can never disagree with itself the way two literals would" (`wake-floor.bats:523-524`). That
helper is the reusable asset; lifting it into a shared bats lib is the clean move.

### Two collateral obligations a change must honour

1. **`CUSTODY_SRC` is a documented three-state oracle**, rendered in `--full` at
   `wrap-ledger.sh:1441-1447` (`cwd` / `none` / `error` / `*`) and described in the header at
   **:767-770**, and it is cited in `docs/plans/CLOSE_INTEGRITY_2026-08-10.md:99,103`. Adding a
   `pane` state means updating the header comment, the `--full` `case`, and that plan doc.
2. **The memo key at `wrap-ledger.sh:376-381` does not include a pane id.** It keys on
   `$WL_TRANSCRIPT|$PWD|$SESSION_FLAG|…|$CC_CUSTODY_BIN|$CC_CUSTODY_DIR`. Two *concurrent* siblings
   have different transcripts so they cannot collide — but a **resumed** session keeps its transcript
   and gets a **renumbered pane** (memory: `resumed-session-loses-terminal-identity`), so a cached
   ledger could be served under a stale pane identity. If the count becomes pane-dependent, the pane
   id must join `_wl_k`. This is the one non-obvious correctness trap in the change.

---

## 6. VERDICT — **DRIVABLE-NOW**

No genuine operator decision exists. Reasons, in priority order:

1. **The crux question is already answered on trunk, twice, in writing.** `bin/cc-custody:35-38`
   (POLARITY: over-count rather than silently drop) and `bin/cc-custody:44-46` (the same rule applied
   to the TTL question) state the invariant. `hooks/session-continue.sh:537-541` applies it to *this
   exact question* — "an unattributable row still counts, and the message HEDGES instead of asserting
   originatorship" — and `tests/wake-floor.bats:584` pins it as a landed test. Choosing among
   count/drop/separate is therefore **determined by evidence**: Option B (drop) is the direction the
   repo has explicitly rejected twice; Option A (count, hedge the wording) is the direction it has
   already shipped. An implementer is *porting a decision*, not making one.
2. **The remedy is fully specified by the backlog title** and its target is one function
   (`wrap-ledger.sh:772-786`). The predicate to port is 7 lines of jq (`session-continue.sh:559-565`).
3. **The blast radius is closed and small**: exactly 3 consumers of the `CUSTODY_OPEN` field
   (§4), no fourth, and the store-level scripts do not read it.
4. **The test work is mechanical**: 3 stub rewrites using a helper that already exists
   (`wake-floor.bats:526-541`), plus new tests mirroring `wake-floor.bats:544-598` at the ledger level.
5. **G2 is clean** — no auth surface, no destructive migration, no navigation pattern, no DB timeout.
   The change is fail-OPEN by construction on both existing arms (`:781`, `:783-784`), and the
   direction of any residual error is *over-count* (a bounded, latched 🔧), never silent loss.

### Two things the implementer must NOT silently decide (they are design, but evidence settles them)

- **`theirs` IS dropped, `unk` is NOT.** That asymmetry is the whole point and is pinned by
  `wake-floor.bats:552` (sibling's row must not convict) vs `:584` (unattributable row still counts).
- **`operator-readout.sh:815-822` must gain the hedge.** Today it renders a flat
  `"N dispatched session(s) NOT returned"`. Once the count is attributed, the two populations need
  the two different sentences `session-continue.sh:684` (assert) and `:687` (hedge) already ship —
  otherwise the readout asserts originatorship over rows the store cannot attribute, which is the
  same alarm-polarity defect one layer up.

### The one thing worth escalating — but it is a SEPARATE item, not a blocker

`bin/cc-offload:561-566` opens custody with **both** identity fields conditional, and the live store
shows the result: **117 open rows carrying neither field**, all `cwd:"/"` cloud fires. Fixing
*that producer* (e.g. always writing a stable originator key for cloud fires) would shrink the
unattributable class to near-zero and make the whole question mostly moot. It is out of this item's
scope, passes the FILED test (why-not-now: different file, different subsystem; why-still-true:
`cc-offload:584` prints the unmanaged case as a supported mode, so it will keep producing them;
who-for: agent work), and should be `cc-backlog add`ed rather than folded in.

### If you want a one-sentence question anyway (there is none that must be asked)

There is no operator-only decision. The closest thing to a fork — *"should an open dispatch that the
store cannot attribute to anybody still block your ✅?"* — is already answered **yes** by
`bin/cc-custody:35-38` and by the landed `hooks/session-continue.sh:537-541`, and re-asking it would
be deference-fishing over a settled invariant.

