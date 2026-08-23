# Custody integrity — why a finished or dying peer vanished silently

**2026-08-23.** Brief: *a finished — or dying — peer session can never vanish without its originator
learning of it.* Baseline handed over: 175 cloud + 4 local custody rows open, 2 local peers dead and
unrecoverable, and a leading hypothesis that cloud sessions are *structurally incapable* of
discharging.

**That hypothesis is refuted, and so is the "unrecoverable" half of the baseline.** Both matter,
because each pointed at a fix that would have been wrong.

---

## 1. What was actually true

| Brief said | Measured | How it changes the fix |
|---|---|---|
| 175 cloud rows, "never discharged" | **220 opens / 45 returns / 0 abandons** in the cloud shard — a 20.5% rate, and the returns are clustered **2026-08-12 → 08-17** | The path is not missing. It **worked, then stopped.** A fix that builds a cloud discharger rebuilds a thing that exists. |
| cloud may have no self-close ⇒ cannot discharge | `scripts/cloud-return.sh` is launchd-driven via `autonomy-sweep.sh` and **ran 20 minutes before this measurement** | Not structural. The sweep is alive and abstaining. |
| panes 377 + 552 unrecoverable | Both panes are dead; **both sessions' WORK IS ON reso `origin/main`** — `c2e16d7d7` (377) and 8 commits `c12612b35..0e6c148dd` (552), each `--is-ancestor` rc 0 | Their disposition is `RETURN`, not `ABANDON`. Recording abandon would have asserted the opposite of what happened. |
| 179 open | **180** — the 180th is `fire-custody-integrity`, the fire that created this session | A blanket reap closes the debt on the session doing the reconciling. |

### The one observation that discriminates

If the cloud lane were structurally incapable of discharging, there would be **zero** returns, ever.
There are 45, and the last is `2026-08-17T09:12:05Z`. Opens continued daily through 08-23:

```
        Aug 12  13  14  15  16  17  18  19  20  21  22  23
opens       14  17  18  18  10  19  20  31  23  16  29   5
returns      3   0  12   5  16   9   0   0   0   0   0   0
```

119 opens and zero returns since 2026-08-18. A capability that ran for six days and then stopped is
a **regression**, not an absence — and the two have opposite remedies.

---

## 2. Root cause — the cloud lane

Three layers, and only the third is the invariant this brief owns.

**(a) The proximate cause of the pile.** Since 2026-08-18 the dominant per-session outcome in
`~/.claude/autonomy/cloud/return.jsonl` is `land-refused` (rc 65 ×34, rc 70 ×46) and `land-cut`
(SIGTERM). `cloud-return.sh:428-437` discharges custody **only on a content-verified land** — by
design, and correctly: *"discharging it over an unverified result would delete the one mechanism
that would have caught this."* So every failed land leaves a debt open. Fail-closed, working as
written. A secondary contributor is 20 `abstain` rows carrying
`HTTP 401 … OAuth access token has expired` from the control plane.

**(b) Why nobody was told.** `cc-offload:562-566` opens custody with `--cwd "$PWD"` and
`${ITERM_SESSION_ID:+--originator-pane …}`. The dispatcher runs under **launchd**, whose cwd is `/`
and which has no `ITERM_SESSION_ID`. Consequently **175 of 175 open cloud rows carry cwd `/`, no
`originatorPane`, and no `notifyBack`** (measured; the shard is `sha256("/")[:32]` =
`8a5edab282632443219e051e4ade2d1d`). cloud-return detects the outcome faithfully and then has no
address:

> **1055 of its 1116 wake attempts recorded `the declaration names no notify-back target — nothing
> to wake`. 61 real wakes. 94.5% of the news produced and discarded.**

And because no interactive session's cwd is ever `/`, every `--cwd .`-scoped consumer
(`wrap-ledger` `CUSTODY_OPEN`, `completion-assert`, `session-continue`'s wake floor,
`operator-readout`) is blind to that shard **by construction**. The debt is filed in a drawer nobody
opens.

**(c) The population nobody had characterised.** Of the 175, **113 never started**: no branch on
`origin` past the 900 s boot budget, no sha ever observed, no local remote-tracking ref. The
dominant cloud "debt" was never work at all. *(Positive control: 56/56 `STALLED` branches DO resolve
a remote ref and 0/113 of these do — the instrument discriminates, it is not just measuring "we
never fetched".)*

## 3. Root cause — the local lane

The local lane is **essentially perfect and must not be touched**: 16 of 18 shards run
`opens = discharges`, and today 6 fires opened and 6 returned. It has two discharge routes, and both
are **in-process on a session that must survive**:

1. `handoff-fire.sh:6688` — `_hf_custody return` inside `sc_announce_before_retire` (self-close).
2. `hooks/mailbox-drain.sh` — discharges by slug on a received `HANDOFF-PING`.

A `kill -9` runs neither. Forensic confirmation on pane 552: `~/.claude/cc-fired/552.json` reads
`"closedAt": null, "succession": null` — it never self-retired.

Measured death taxonomy (A/B on the real binary, counting attributed `Session ended` lines):

| death class | EXIT trap | SessionEnd hook | out-of-process observer |
|---|---|---|---|
| clean self-close | yes | yes | n/a |
| SIGINT / SIGTERM / SIGHUP | yes | **yes** | none |
| **SIGKILL** (`kill -9`, `timeout -k`) | **no** | **no** | none |
| crash / OOM | n/a | no | `cc-reaper` pages *only if a registry row survives* |
| usage-limit or context ceiling (**process still alive**) | n/a | **no** | none |

Two further findings make this worse than "a hook is missing":

- **The janitor destroys the key.** `cc-reaper`'s `clear_fired_marker` does
  `rm -f "$FIRED_DIR/$pane.json"` (`bin/cc-reaper:830,834,1879`) — the stamp carrying the discharge
  marker. Measured **157** such GCs.
- **Nothing out-of-process knows the word.** All 20 reap/orphan/alarm scripts and every registered
  `SessionEnd` hook contain **zero** occurrences of `custody`.

**The unifying shape: every existing sensor asks the peer, or asks the originator's own turn. When
the peer is killed and the originator is a cron job, there is no one left to ask.**

---

## 4. The fix — `scripts/custody-deathwatch.sh`

One out-of-process pass, wired into the already-launchd-resident `autonomy-sweep.sh`:

1. Read the open set **store-wide** — `cc-custody list --open --json` with **no `--cwd`**. The only
   consumer that deliberately drops the cwd scope, which is exactly how it sees the `/` shard.
2. Ask a **three-valued** oracle that does not depend on the peer's cooperation —
   `ALIVE` (never report) · `GONE` (report at any age — the abnormal-death fast path) ·
   `UNKNOWN` (a lookup miss is not absence; may never mint a death).
3. Report once per peer to an address that exists **by construction**: the originator's inbox when
   its pane is alive, else ONE aggregated `cc-backlog needs` row that `operator-readout` renders.

### The property that matters most

```
REPORT  ⇔  ( oracle says GONE )  OR  ( row is STALE, age ≥ CC_CUSTODY_TTL_HOURS )
```

The second arm reads only the row's own `ts`, which is always present. **An oracle outage degrades
the WORDS of the report, never its existence.** The alarm keys on the store, not on the sensor —
which is precisely what the six-day silence needed, since cloud-return abstained *correctly* on a
401 control plane and told nobody. Correct abstention is still silence.

### Failure direction

It can only ever **ADD a notification**. It cannot discharge custody, close a row, signal a process,
or touch a branch. Worst case is operator noise — bounded by a per-marker latch (once ever) and by
aggregation (one row per pass, not one per peer). Silence is what it replaces, and silence has
already cost 62 content-stranded commits across 21 branches. Uncertain about liveness → still report
(stale floor). Uncertain about the peer → never mint GONE from a failed oracle. Uncertain about
anything → never discharge.

### Four defects found in the fix before it landed

Each is now an anchor-checked regression arm, red against the reconstructed pre-fix line.

| # | Defect | How it was caught |
|---|---|---|
| 1 | `IFS=$'\t' read` — **tab is IFS whitespace**, so the one marker-less row shifted every field left, a cwd path became a "pane", and the pass judged **a session running at that moment** to be dead | dry run against the live store |
| 2 | pane liveness used `index()` — a dead pane `60` matched live `602`/`600`/`605` | dry run |
| 3 | **the oracle reported success while knowing nothing** — `cc-cloud list --json` (no `--state`) exits 0 with 149 KB of rows carrying *no state key*, so every row fell through `.state // "UNKNOWN"` while the ledger logged `cloud_oracle_ok:true` | measuring the oracle against the live control plane |
| 4 | 18 **dead assertions** — bare `[[ … ]]` and `! diff -q` are unreachable under errexit, so several cases could not fail, including the anchor checks the regression arms depend on | `ship-land`'s dead-assertion gate |

Defect 3 is the sharpest: the row-level answer is `UNKNOWN` either way, so **only the ledger flag
distinguishes a working sensor from a blind one** — and a blind sensor claiming success is exactly
how a six-day outage stays invisible.

### Proof: a SIGKILLed peer reaches its originator

Real pane 610, real `kill -9`, control arm included so the demo could have failed.

```
[2] CONTROL — peer ALIVE
    custody-deathwatch: open=1 alive=1 gone=0 unknown=0 → reported=0
    inbox 602.md: ABSENT
[3] kill -9 85907          → pane 610 GONE from cc-pane list
    custody still open: 1     ← the peer discharged nothing on its way out
[4] custody-deathwatch: open=1 alive=0 gone=1 unknown=0 → reported=1 (direct=1)
[5] /Users/chrisren/.claude/mailbox/602.md  313 bytes  mtime 2026-08-23T17:53:53Z
    │ CUSTODY-DEATHWATCH: the peer you fired (fire-demo-peer, target 610) is GONE and has
    │ NOT returned — its custody debt has been open 0h. Collect+land its work, then
    │ `cc-custody return DEMO-SIGKILL`; …
```

`mailbox-drain` then delivered it to the originator as peer mail in the same turn.

---

## 5. Reconciliation of the 179 (180) rows

By evidence, per row. **Nothing silently dropped, and no blanket reap** — a reap closing a debt over
live work is the worse failure. Full table: `/tmp/custody-research/RECONCILIATION.tsv`.

| Disposition | n | Evidence |
|---|---:|---|
| `ABANDON-never-started` | **103** | no origin ref past the boot budget **AND** no sha observed **AND** no remote-tracking ref — positive-controlled — **AND the control plane says the peer is idle** (see the correction below) |
| `KEEP-OPEN-not-idle` | **10** | git-side identical to the row above, but the control plane reports `requires_action` ×7, `running` ×1, `WORKER_STATUS_UNSPECIFIED` ×2 |
| `KEEP-OPEN-real-branch` | 36 | branch on origin + sha observed; commits not on trunk |
| `KEEP-OPEN-land-refused` | 23 | as above, plus a `.land-refused` artifact naming a mechanical blocker |
| `KEEP-OPEN-off-trunk` | 3 | branch deleted from origin, but the observed sha is present locally and is **not** an ancestor of `origin/main` |
| `RETURNED` | 2 | panes 377 + 552 — work content-verified on reso `origin/main` |
| `KEEP-OPEN-alive` | 2 | panes 600 and 602, present in `cc-pane list` |

Store went **180 → 80 open**. The 62 cloud rows with branches hold **real commits that are on no
trunk** — a landing backlog, not a bookkeeping artifact; closing them would erase the only record
that the work exists.

### The correction I had to make — a false close, caught and reversed

**My first pass abandoned 113 rows, and 10 of them were live peers.** The never-started test used
only git-side evidence — no origin ref, no sha observed, no remote-tracking ref — and all three are
*true of a session that is blocked waiting for input*. A `requires_action` peer has not pushed a
branch **precisely because it is stuck**, not because it is gone. Abandoning it records "this peer
is gone, nothing is owed" over a peer that is alive.

The overlap was exactly total: `comm -12` of the 113 abandoned against the 10 non-idle returned
**10 of 10**. All ten were re-opened (`cc-custody open` appends, and the fold takes the latest
verdict per key) and each verified back to `OPEN`.

Two lessons, and the second is the sharper one:

- **A liveness test must include an axis that can distinguish "never ran" from "ran and is
  waiting".** Git-side evidence cannot: both look like silence on the remote. Only the control
  plane separates them.
- **The warning was already written down when I acted.** The census subagent's adversarial pass
  said *"a blanket reap would have been wrong on all 10"* — I ran my own git-side census, agreed
  with its shape, and executed before reading its adversarial section. Reading a report's findings
  and skipping its refutations is how a measured warning becomes a repeated mistake. Same family as
  [[work-item-citation-refutes-its-own-remedy]].

This is also why the deathwatch itself **never discharges**: had this been the mechanism rather
than a human-directed reconciliation, the same error would have run unattended every 300 seconds.

## 6. What this does NOT fix

Named so the next session does not read a closed loop where there is none.

1. **The lands still fail.** rc 65 / rc 70 since 2026-08-18 is the proximate cause of the pile and is
   untouched here. The deathwatch makes it *visible*; it does not make it land.
2. **The cloud control-plane 401** (`account next`) is unrepaired; the cloud oracle degrades to
   `UNKNOWN` and the stale floor carries the report.
3. **62 cloud rows hold unlanded commits** and need a land-or-discard decision each.
4. **`cc-reaper` still deletes the discharge key** (`clear_fired_marker`). The deathwatch does not
   depend on that stamp, so it is unaffected — but any future marker-based discharger would be.
