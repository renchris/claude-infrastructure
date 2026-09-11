# The third dispatch in eight hours: `2a65b9bf722d` is not unfinished, it is **operator-gated**

**Date:** 2026-09-11 · **Subject:** cc-backlog `2a65b9bf722d` ("ProposeGoal (`tengu_propose_goal`)
is default-off upstream — adopt when the flag flips") · **Venue:** Anthropic-managed cloud VM,
Claude Code **2.1.268** (`/opt/claude-code/bin/claude`, 218,602,992 B). · **Predecessors:**
`docs/research/propose-goal-flag-recheck-2026-09-10.md`,
`docs/research/propose-goal-flag-recheck-2026-09-11.md`. · No flag flipped, no setting written,
no live file touched (C10).

## 🚦 Disposition: the row stays OPEN on its merits, and the **cloud venue is PARKED**

The premise is **NOT REFUTED** — independently re-verified below. So the row is right to be open,
and nothing here asks to close it.

What this note adds is the disposition its two predecessors did not reach. Both ended by re-stating
"still off" and landing prose; the row was re-dispatched both times. The remaining step is not work
— it is **one store edit on the operator's box**, and a cloud VM cannot make it. That is a park, and
`docs/parks/2a65b9bf722d.md` is it.

## 1. The loop, measured

Every commit below is on `origin/main`. Three dispatches, one verdict, eight hours twenty minutes:

| when (UTC) | dispatch | landed | verdict |
|---|---|---|---|
| 08:13Z | #1 | `36859c6e` re-anchor | still OFF at 2.1.267 |
| 11:53Z | #2 | `377f12f5` `eb858cd3` `7b286541` `89dab9dd` — the watcher + note | still OFF at 2.1.268 |
| 13:00Z | — | `8c26adeb` (follow-on: a padded `wc -l` inverted the binary arm) | — |
| **16:31Z** | **#3 (this one)** | this note + the park | **still OFF at 2.1.268** |

Dispatch #2 built the right instrument and named the right handoff. It could not *apply* it, because
the falsifier lives in `~/.claude/autonomy/backlog.jsonl` on the desk. Landing a fourth prose note
would not change that either — which is the whole reason this one parks instead.

## 2. The repoint has not happened — and that is a measurement, not an inference

The brief that fired this session quotes its own re-run of the row's **stored** probe:

```
probe: jq -es 'any(.[]; .cachedGrowthBookFeatures.tengu_propose_goal == true)' ~/.claude*/.claude.json
output: false
```

That is the incumbent one-liner verbatim, not `--falsify`. So dispatch #2's §0 handoff is still
outstanding, and the brief's own quoted output is the hole it describes. Run verbatim on this VM:

```
$ jq -es 'any(.[]; .cachedGrowthBookFeatures.tengu_propose_goal == true)' ~/.claude*/.claude.json
jq: error: Could not open file /root/.claude*/.claude.json: No such file or directory
false
rc=2
```

The desk reads rc 1 from this line and the VM reads rc 2, and the word printed is `false` in both
cases. Every consumer folds both into "non-zero ⇒ keep the row open", so the row cannot learn the
difference between *the flag is off* and *the instrument could not be run here*.

## 3. Independent re-verification at 2.1.268

`scripts/propose-goal-flag-watch.sh`, from trunk, on this VM:

```
(1) FALSIFIER  rc=1  off, on a healthy instrument — keep waiting
    window 604800s · 1 cache(s) · 1 fresh · 0 unreadable · fresh-true 0 · stale-true 0
  fresh  0h        tengu_propose_goal=ABSENT   /root/.claude.json

(2) BINARY     rc=1  gate still default-false
    subject /opt/claude-code/bin/claude
    gate    function syt(){return I("tengu_propose_goal",!1)}
    control ProposeGoal×18 · tripwire tengu_×1890
```

`--health` rc 0 (a cache refreshed inside the window), `--falsify` rc 1, `--binary` rc 1,
`--selftest` **18 ok · 0 failed**. The gate symbol is still `syt` — same build as dispatch #2, so
§2 of that note is neither confirmed nor challenged here. The feature is **not** removed upstream.

### 3.1 The control set has three stable members and one that varies — correcting a claim in place

Dispatch #2's §1 wrote *"All four values reproduce"* of its positive control. Three do. The fourth
does not, and was already on record as not doing so:

| control key | A12-skeptic2 (5 files, 09-08) | recheck 09-10 | recheck 09-11 | **here, 09-11** |
|---|---|---|---|---|
| `tengu_saffron_wren` | true ×4 | true | true | **true** |
| `tengu_hushed_lark` | 5 ×4 | 5 | 5 | **5** |
| `tengu_rosy_wren` | absent ×5 | ABSENT | ABSENT | **ABSENT** |
| `tengu_umber_kestrel` | **F / F / T / F / T** | ABSENT | ABSENT | **present, `false`** |

`umber_kestrel` was measured as per-identity-varying on 2026-09-08, and the 09-10 note flagged it as
the varying member. The 09-11 note's "all four reproduce" was therefore a coincidence of two VMs
drawing the same assignment, not a property of the control — left unmarked, the next reader meets a
legitimate `ABSENT → false` transition and reads it as the instrument breaking.

**This makes the control stronger, not weaker.** A control set that reads identically forever cannot
distinguish a live cache from a frozen artifact. This one demonstrably moves, and the instrument
renders the move correctly — `has()`, not `//`, so present-and-false renders `false` rather than
`ABSENT`, which is exactly the distinction §4 of dispatch #2 built it for. Census otherwise
reproduces: 623 keys, 618 `tengu_`, **0** keys matching `goal|propose`, cache stamped
`2026-09-11T16:31:33Z` (this session's own boot).

## 4. The prescribed step is verified against its consumer, not merely plausible

Dispatch #2 prescribed the replacement probe in prose. Before parking on it, it was checked against
the code that will actually run it — `run_falsifier` at `bin/cc-premise:1362`:

| what the runner does | source | does the prescribed step survive it? |
|---|---|---|
| `subprocess.run(["/bin/sh","-c",cmd], cwd=REPO or None)` | `cc-premise:1389-1394` | **yes** — `cwd=REPO` is the checkout root (`_default_repo()`, realpath of `bin/cc-premise` one level up), so the *relative* `scripts/propose-goal-flag-watch.sh` resolves. The command word is `bash`, so `/bin/sh` never interprets the script. |
| `timeout=FALSIFIER_TIMEOUT_S` = **20 s** | `cc-premise:241` | **yes** — measured 19 / 19 / 16 ms on this VM, three orders of magnitude of headroom. |
| exit 0 ⇒ `falsified` (retract); non-zero ⇒ advisory | `cc-premise:1366-1380` | **yes, drop-in** — the replacement keeps that polarity exactly. |
| `cc-backlog falsify` **runs the probe before storing** and REFUSES at rc 5 if it exits 0 against a live row | `bin/cc-backlog` `cmd_falsify` | **yes** — it exits 1 on the desk (off, healthy instrument), so it passes the screen. |

One caveat the operator should know rather than discover: `REPO` resolves to the **shared checkout**
(`~/Development/claude-infrastructure`, the symlink source for `~/.claude`), so the stored probe
reads whatever that checkout currently has at `scripts/propose-goal-flag-watch.sh`. The file is on
trunk as of `8c26adeb`; the probe is only as converged as that checkout is.

## 5. Positive control: the replacement would actually FIRE

A falsifier whose job is to stay quiet for months is indistinguishable, on every quiet day, from one
that can never speak. So the arm that matters was driven directly, against fixtures, on this VM:

| fixture | required | measured |
|---|---|---|
| fresh cache, `tengu_propose_goal: true` | rc **0** — RETRACT the row | **rc 0** |
| fresh cache, present and `false` | rc 1 — off, keep waiting | **rc 1** |
| **40-day-stale** cache, flag `true` | rc 2 — NON-VERDICT, not a reading | **rc 2** |
| population that does not exist | rc 2 — NON-VERDICT (the incumbent answers "off" here) | **rc 2** |

Row 1 is the one this row exists for, and it works. Rows 3 and 4 are the two states the stored
one-liner spends the word `false` on.

## 6. Dispatcher vintage: BEHIND, and now two trunk-moves behind

| read | firing `bin/cc-dispatch` blob | `origin/main:bin/cc-dispatch` | verdict |
|---|---|---|---|
| dispatch #2 (11:53Z) | `9109de61dc7a…` | `e61bcbfc657a…` | DIFFERENT |
| **this one (16:31Z)** | `9109de61dc7a…` | **`27c461a5f1a4…`** | **DIFFERENT** |

The firing blob is unchanged across both dispatches while trunk's has moved twice. Landed is not
live. This is a convergence fact about the deploy layer, not a defect in anything read above — but
it is the likeliest reason the row was re-fired three times in one day by a dispatcher that has not
yet seen the watcher land.

## 7. What was NOT established

- Whether the flag is on for **any** identity anywhere. Seven caches reading absent is absence of
  observation for those identities; GrowthBook targeting is per-identity, and §3.1 is direct
  evidence that assignments differ between them.
- Anything new about **adoption cost** (the 500-char `rAt` cap, the `alwaysAsk` upgrade, the
  plan-mode throw). Unchanged, un-re-measured, and actionable only once the flag flips.
- Whether the gate symbol has moved again. Same build as dispatch #2, so this pass cannot say.
- Whether the watcher should be **scheduled**. Still deliberately not wired to launchd or a sweep
  lane, for dispatch #2 §8's reason: the dispatcher already runs the row's falsifier, so a scheduled
  job would be a second watcher. C10 forbids a worker touching launchd in any case.

## 8. The handoff

`docs/parks/2a65b9bf722d.md` carries it in the machine-readable form `cloud-return.sh` step 8 and
`bin/cc-eligible` both read. In prose, the single step is:

```sh
# on the desk, any cwd — cc-backlog resolves its own store
cc-backlog falsify 2a65b9bf722d --probe "bash scripts/propose-goal-flag-watch.sh --falsify"
```

Once that is stored, the row is a watch row with a watcher that can actually fire, and it should be
unblocked and left alone until it does.
