# postland-verify "INERT" (`01ab05685857`) — verdict, and the residual it was hiding

**Date:** 2026-09-04 · **Venue:** cloud VM (Ubuntu, off-box), dispatched worker
**Row:** `01ab05685857` — *"postland-verify is INERT — newest GREEN stamp 46h old (max 24h), so
nothing is re-proving trunk; this is how 3 red suites went unnoticed"*
**Trunk read at:** `a03a4b63` · **Dispatcher blob:** `646b8a652e71dd5e5e506dffe23725437accea6b`,
**EQUAL** to `origin/main:bin/cc-dispatch` — the dispatcher that fired this session IS trunk, so no
landed-but-not-live caveat applies to the brief itself.

## Verdict in one line

**The row as filed is CURED on trunk** — its premise refuted and its harm instrumented, by two
commits both asserted ancestors of `origin/main`. **The residual is not the row's own subject**: the
instrument that cures it is macOS-only and returns `[]` on Linux, and that is what this session
repaired.

## 1. The row's premise is false, and trunk says so

`675596dd` (2026-09-03, `git merge-base --is-ancestor 675596dd origin/main` → 0) adjudicates the row
directly:

> The premise is false and the harm is real, which is why the row survived two triages: the daemon
> IS loaded and IS stamping (measured 2026-08-16, launchctl pid 85038, stamps advancing), and trunk
> still went unproven for days.

and corrects the quantity the row names:

> THE MEASURE IS THE UNPROVEN SPAN, NOT THE NEWEST GREEN'S AGE. The row's own wording is the sampled
> value, not the condition, and keying on it reds a healthy machine.

So "postland-verify is INERT" is a mis-description of a real famine. The famine's *cause* — the
verifier stamping `cut` rather than `green` — is a different row (see §4).

## 2. The harm ("3 red suites went unnoticed") is instrumented, on two surfaces

| Surface | What landed | Sha | Ancestor of `origin/main` |
|---|---|---|---|
| Nightly page | `nightly-regression.sh` step **5b** `postland_green_starvation` — reds when trunk carries content nothing re-proved past `POSTLAND_GREEN_MAX` (86400s) | `675596dd` | ✅ asserted |
| Operator board | `bin/cc-blockers` alarm `green-starved` / `UNCERTIFIED` — the state between `trunk-red` and `never-green` | `1f5bd304` | ✅ asserted |

Both are wired, not merely present: `nightly-regression.sh:666` calls it through `run_check`, and
`bin/cc-blockers:1454`'s `LAND_SEL` includes `green-starved` so it renders in the LAND-PIPELINE
table and not only in `--json`.

**Verified here, off-box:** `bats -f "nightly 5b" tests/deploy-live.bats` → **7/7 ok**. That half of
the cure needs nothing.

## 3. The residual, which is why this session is not a no-op

The *other* half — the `cc-blockers` alarm — could not be verified off-box at all, and then could
not RUN off-box at all. Two defects, one in the proof and one in the product.

### 3a. The RED-proof was macOS-only (`tests/cc-blockers.bats`)

`mkstamp` aged every fixture with `date -v-<age>`, which is BSD-only. On Linux the command
substitution comes back **empty** and `touch -t ''` fails inside the fixture, so no assertion is ever
reached:

```
not ok 1 alarm green-starved/UNCERTIFIED: the verifier is alive, the newest green is past the budget
#   `mkstamp r1 red 1M; mkstamp h1 hung 2M; mkstamp g green 30H' failed
# date: invalid option -- 'v'
```

All **10** `green-starved` tests died that way — the RED-proof for this row's own cure had zero
coverage on the one lane that could have run it. This is the identical failure
`tests/autonomy-sweep.bats:227` was written for (*"nine cases died that way, and the reds were read
twice as evidence about the code under test rather than about the clock helper"*), so the repair is
that established helper — **BSD first, GNU as the fallback**, because macOS `date -d` means
*daylight saving*, not *date string*, and a GNU-first probe would succeed there and mis-date every
fixture — extended to the `M` (minute) unit this file also uses, plus signed-offset and ISO variants
for `ts_at` / `ts_acct` / `mkdeploy`.

### 3b. The ALARM ITSELF was macOS-only (`bin/cc-blockers`)

With the clock fixed, the tests reached their assertions and **7 of 10 still failed** — because the
alarm never fires on Linux. Root cause is one line, `bin/cc-blockers:300`:

```sh
mtime() { stat -f %m "$1" 2>/dev/null || true; }   # BSD stat
```

`mtime` is the **single clock every LAND-PIPELINE alarm reads** — `newest_ts`, `green_ts` and
`land_ts` all come through it. On any non-macOS host all three read empty, every alarm abstains, and
the board prints `[]` — fail-open, silently, for the whole platform.

**Measured**, with the exact `green-starved` fixture (30h-old green, a land on top of it, a fresh red
stamp): `cc-blockers --json` → `[]`.

The repair deliberately does **not** copy the repo's usual `stat -f %m … || stat -c %Y …` one-liner
(`bin/cc-idl:52`, `bin/cc-value:463`, and 60 more), because that idiom is itself wrong on Linux and
the difference is measured, not stylistic. GNU `stat -f` is *filesystem status*, so it does not fail
cleanly:

```
$ stat -f %m /tmp/probe ; echo rc=$?
  File: "/tmp/probe"
    ID: 0        Namelen: 255     Type: ext2/ext3
Block size: 4096       Fundamental block size: 4096
Blocks: Total: 66053021   Free: 64124762   Available: 7783872
Inodes: Total: 16777216   Free: 16618526
rc=1
$ stat -f %m /tmp/probe 2>/dev/null || stat -c %Y /tmp/probe 2>/dev/null
  File: "/tmp/probe"
  … six lines …
1788518208            ← the answer, appended to the garbage
```

It prints a six-line block to **stdout** and exits 1, so under `||` the second call appends the real
epoch to that block and the caller gets garbage with the answer buried in it — which the `*[!0-9]*`
guards downstream then reject, fail-open again by a longer route. Hence the dialects are selected on
**whether the output is an epoch**, never on the exit code. BSD is still tried first, so the
production box's path is byte-unchanged.

## 4. What is NOT this row, and who owns it

The verifier's `cut` famine — the reason greens are scarce in the first place — is
**`782607797fc5`**, and it is genuinely operator-gated. `docs/research/blocked-tail-triage-2026-08-16.md:149`
classifies it `TRULY-OPERATOR`: *"sudo — `sudo dtrace` is SIP/root-gated; no unprivileged way to name
a signal sender on macOS"*. `BACKLOG_DRAIN_24_7.md:30501` has its symptom live (kills by signal 9/15,
"sender unidentified"; 84 of the last 126 stamps `cut`), and `675596dd` corroborates the lifetime
mix at **397 cut vs 88 green (13.7%)**. Nothing about it is reachable from a cloud VM, and no work
here touches it. `5511ea906e2e` is downstream of the same signal-kill, not a deploy fault.

## 5. Evidence — what was actually run, off-box

Venue provisioned with `scripts/cloud-venue-provision.sh` → bats **1.13.0**, shellcheck **0.11.0**
(the versions this repo pins; the distro's 1.10.0/0.9.0 are the ones that silently under-run).

| Check | Result |
|---|---|
| `bats -f "nightly 5b" tests/deploy-live.bats` | **7/7 ok** — the nightly half of the cure needs nothing |
| `bats tests/cc-blockers.bats` on **`origin/main`** (control, same box) | **42 ok / 63 not ok** — the entire alarm block (tests 13–67) plus every relogin test dead |
| `bats tests/cc-blockers.bats` **patched** | **103 ok / 2 not ok** |
| `shellcheck bin/cc-blockers` | rc 0 |
| `test-hermeticity` · `test-walltime` · `subshell-cleanup` · `bats-testname-eval` · `bats-kill-guard` · `self-path` · `permission-gate` · `alarm-polarity` lints | all rc 0 |
| `bats-assert-liveness.py` · `bats-shellcheck-lint` · `bats-shim-parity-lint` | rc 0 |

**The 2 residual failures are pre-existing on trunk (both appear in the `origin/main` control above)
and are irreducible macOS coupling, not this row's condition:**

- `M8 POSITIVE CONTROL … sensors 5/5 readable` — the roster counts `/bin/launchctl`, which does not
  exist on Linux (`launchctl:x`, 3/5 here). launchd is macOS; the assertion cannot hold off-box by
  construction.
- `land-lock-hung renders in the LAND-PIPELINE table` — `land_holder_rows` delegates to
  `scripts/land-lock.sh --alarms`, which owns the lock's `pid`+`lstart` semantics and reads BSD
  `ps -o lstart=`. A separate subject and a separate script; deliberately not widened into here.

## 6. Disposition

- **`01ab05685857` is DONE.** Cure shas `675596dd` and `1f5bd304`, both asserted ancestors of
  `origin/main`. Not re-derived.
- **The residual repaired here** is a different fault the row's cure was hiding: the alarm and its
  proof were macOS-only, so the off-box lane — the same lane whose hermetic acquittal step 5b reads
  (`offbox/<tree>.json`, `scope:"offbox-hermetic"`) — could neither run the alarm nor prove it.
- **Not filed, deliberately:** the two macOS-coupled tests above. Neither is a defect (launchd
  genuinely is not on Linux), and `782607797fc5` already owns the famine's cause.
