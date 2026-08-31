# The off-box census was taken in the wrong venue — and one of its seven reds is a real bug

*2026-08-31, twelfth dispatch on `BACKLOG_DRAIN_24_7`'s own row (`70f0001c657b`), measured inside a
cloud VM. Plan: `docs/plans/BACKLOG_DRAIN_24_7.md`.*

## The cell this takes, and the answer that retires it

The plan's fifth-lock addendum closed by naming its own next step:

> ⚠️ **`scripts/offbox-excluded.manifest` is deliberately untouched**, and the census is the reason it
> stays that way rather than the reason to write into it: a cause was measured for NONE of the seven,
> that file's own contract is *"every entry is a MEASUREMENT, not a judgement"* … A census is the
> INPUT to that work, not the work — and it is now cheap for the next link, which is the whole change.

The seven were `gate-home-isolation` 15 · `bats-shellcheck-lint` 1 · `land-gate-cas` 1 ·
`land-gate-memo` 1 · `land-inflight` 1 · `tsv-field-collapse` 1 · `test-hermeticity-lint` (no
verdict). A cause is measured below for every one of them, each with a control.

🚨 **But the manifest is STILL untouched, and this time the reason is that the entries would be
WRONG rather than merely unjustified.** `.github/workflows/hermetic.yml:133` runs the shard job — the
one that actually executes suites — on **`macos-latest`**. The census that named these seven ran in a
**Linux cloud VM, as uid 0**. Those are different machines in every axis each of these failures turns
on, and `scripts/offbox-excluded.manifest` is a claim about the first one.

**Five of the six reds are properties of the VM that DO NOT EXIST on the producer.** An entry for any
of them would assert, in a file whose header says *"every entry is a MEASUREMENT, not a judgement"*,
a measurement never taken on the machine the file describes — and would suppress a suite that passes
there. That is precisely the *"place to hide a real regression"* the addendum above refused to create.

**The trap is structural, and `scripts/offbox-run.sh` names it in its own header without drawing this
conclusion:** *"ONE IMPLEMENTATION, TWO CALLERS. `.github/workflows/hermetic.yml` runs this, and so
can a human reproducing a CI red on their own box — same classifier, same bound, same fold."* That
shared implementation is right, and it is exactly what makes the rows it prints in a container look
like producer rows. The classifier is identical; the **box** is the measurement. Reproducing a CI red
is what the second caller is for; *originating* an exclusion from it is not.

## The causes, one per suite

Every row below was reproduced twice, deterministically, through the producer's own runner
(`scripts/offbox-run.sh suites`, fresh empty `$HOME`, `env -i`, GNU coreutils 9.4, bash 5.2.21,
shellcheck 0.11.0, bats 1.13.0 — the venue provisioned by `scripts/cloud-venue-provision.sh`).

| suite | ok/notok here | measured cause | on `macos-latest`? |
|---|---|---|---|
| `gate-home-isolation` | 8 / 15 | subject is **APFS `cp -Rc`** | **cannot fire** — the runner is macOS |
| `bats-shellcheck-lint` | 27 / 1 | **`MAX_ARG_STRLEN`**, a Linux-only cap | **cannot fire** |
| `land-gate-memo` | 10 / 1 | **uid 0 ignores `chmod 000`** | **cannot fire** — runners are non-root |
| `land-inflight` | 8 / 1 | **no `en_CA.UTF-8` locale** | **cannot fire** |
| `tsv-field-collapse` | 33 / 1 | pins a **bash 3.2** splitting quirk | passes there (delisted 08-13, green 34/34) |
| `land-gate-cas` | 19 / 1 | 🚨 **a real portability bug** — see below | **would fire on any Linux host** |
| `test-hermeticity-lint` | 82 / 0 | **green.** Its "no verdict" was the 300 s bound; it needs 441 s | unmeasured there |

**`gate-home-isolation`.** `ship-land.sh:1673` isolates `$HOME` with `cp -Rc` — APFS clonefile, and
the file says so: *"MECHANISM: APFS clonefile, measured on this box."* GNU coreutils has no `-c`
(measured: `cp: invalid option -- 'c'`), so the clone always fails, the documented **fail-open** path
runs the gate against the live `~/`, and the 15 assertions that isolation *was applied* cannot hold.
Cases 19–20 — *"FAIL OPEN when the APFS clone itself fails"* — are green, which is the control: the
suite's own fail-open cases pass here precisely because that is the branch this box always takes.

**`bats-shellcheck-lint` — and this refutes the plan's own note on it.** The census recorded *"27/1,
an rc-126 past-the-pipe-buffer cell."* No pipe is involved. The case builds a fixture the suite
requires to be `≥ 87122 B` (its "inverting floor") and passes it in a **single environment string**;
the real size is **162,692 B**. Linux caps one arg/env string at `MAX_ARG_STRLEN` = **131,072 B**,
measured on this box at exactly that boundary — 131,000 B execs, 131,072 B is `E2BIG`. So `env` cannot
exec and exits **126**, the exact rc observed:

    env "CC_BATS_SC_OWN=$big" /bin/true   → /usr/bin/env: Argument list too long   rc 126   (162,692 B)
    env "CC_BATS_SC_OWN=$small" /bin/true → rc 0                                            ( 61,892 B)

macOS has no per-string cap, only a 1 MiB total `ARG_MAX`, which 162 KB fits inside. The suite's
floor is a real requirement and it lands the fixture past a limit that exists on only one platform.

**`land-gate-memo`.** The case makes a memo entry unreadable with `find … -exec chmod 000` and asserts
the checker is re-invoked. uid 0 ignores the mode bits, so the entry is read and nothing re-runs:

    uid 0      → cat: prints the file
    uid 65534  → cat: Permission denied

A container running as root is not a property of "off-box"; GitHub's runners are non-root.

**`land-inflight`.** The helper is `LC_ALL=en_CA.UTF-8 bash -c …`, and the suite's comment says *"The
stub branches on the LC_ALL string, so this needs no locale to be installed."* True of the stub, false
of **bash**, which prints `bash: warning: setlocale: LC_ALL: cannot change locale (en_CA.UTF-8)` to
stderr on a box carrying only `C`, `C.utf8` and `POSIX`. Bats folds stderr into `$output`, so the
warning becomes its first line. **The discriminator is inside the suite:** three cases call that same
helper, and only case 1 inspects `$output` (`[[ "$output" == "$LIVE "* ]]`, prefix-anchored). Cases 3
and 4 assert `[ "$status" -eq 0 ]` alone and pass. Exactly the one assertion a prepended line can
break is the one that breaks.

**`tsv-field-collapse`.** §1 case 3 asserts `IFS=$'\001' read` does **not** split, a bash internal
CTLESC quirk; the suite's header states its subject as *"a wrong belief about how **bash 3.2**
splits."* bash 5.2.21 splits normally — `[x||y]` where the case demands `[x..y||]` — under `LC_ALL` of
`C`, `C.UTF-8` and unset alike, so locale is excluded as the variable. Its `\037` sibling passes on
both platforms, which is the control that attributes the failure to `\001` specifically rather than to
`read`. macOS ships bash 3.2, and the producer measured this suite green at 34/34 on 2026-08-13.

**`test-hermeticity-lint` is not a red at all.** It is **green, 82 ok / 0 not ok**, in **441 s**. The
census's "no verdict" was the 300 s per-suite bound doing its job — a cut, which by `offbox-run.sh`'s
own R6 rule *"proves nothing"*. No entry is warranted on this evidence: whether it overruns on the
producer's hardware is unmeasured, and a cost exclusion needs the cost measured **there**.

## The one that was not the venue's: `scripts/land-lock.sh` cannot take the landing mutex on Linux

`land-gate-cas`'s single red is `true concurrency: two real landers race`. The loser's rc file was
absent — and the racer's captured output says why:

    /home/user/claude-infrastructure/scripts/land-lock.sh: line 305: File: unbound variable

**Driven directly, outside any harness**, over a lock dir holding a dead pid:

    pre-fix    rc 1   `line 305: File: unbound variable`   — the mutex is never acquired
    post-fix   rc 0   `land-lock: acquired (no wait)`      — the dead holder is reaped

**The mechanism.** All five stat sites in that file used a bare BSD `stat -f %m … 2>/dev/null || echo
<default>`. GNU's `-f` is `--file-system`: it prints a filesystem **report on stdout** and exits 1.
`|| echo <default>` does not replace stdout already written, so `$(…)` captures the report *and* the
default, concatenated. Four of the five sites feed that capture to **arithmetic**, where `set -uo
pipefail` (line 42) makes the report's first bare word — `File` — fatal:

    captured = $'  File: "/tmp/x"\n    ID: 0 …\nInodes: Total: … Free: …\n0'

So on any Linux host the machine-wide landing serializer **dies at the first stat once the lock
directory exists** — every reap, every TTL question, every `--status` over a held lock. The fifth site
(`lock_generation`'s `%i`) is not arithmetic and so survives, degrading worse than it looks: the
generation token becomes the same constant filesystem report for every generation, so the CAS meant to
detect *"the lock changed under me"* compares **equal always**.

**This class is already known to this repo, and its cure is already written down.**
`hooks/lib/mailbox-pending.sh` § PORTABLE MTIME states it exactly — *"Try the flag whose
wrong-platform behaviour is an ERROR first"*, because BSD `stat` has no `-c` and **errors**, while GNU
`stat` has a `-f` that **succeeds at something else**. That header also says: *"SCOPE. 51 further call
sites carry the same idiom and the same latent bug … They are NOT touched here, and NOT yet in the
backlog — the worker that found this had no reachable store."* This is one of those sites, and it is
the sharpest instance of the class: elsewhere it yields a wrong number, here it is `set -u` fatal.

**Fixed, both directions driven on one box.** `ll_mtime` / `ll_inode` apply the SSOT's order reversal
and print **nothing** when the answer is unknowable — which is the half that makes each call site's own
`|| echo <default>` mean what it has always claimed to mean. Behaviour on the fleet's platform is
unchanged by construction, and that is asserted rather than argued: `tests/land-lock.bats` runs
**25/25 green under a `$PATH` stat shim with BSD flag semantics** (no `-c`, `-f` takes a format).

**A/B through the producer's own runner, same box, same commit but for this file:**

    suite                      pre-fix        post-fix
    tests/land-lock.bats       11 ok / 14     25 ok / 0      green
    tests/land-gate-cas.bats   19 ok /  1     20 ok / 0      green

`tests/land-lock.bats` was not in the census's 33-suite selection and was red 14 on pristine trunk —
an eighth red nobody had counted. **One fix in one file cured 15 off-box failures across two suites.**

**Four cases added**, each stubbing `stat` so both platforms' semantics are exercised on either
platform — the whole defect was one platform's behaviour being invisible from the other. Negative
control against pre-fix `land-lock.sh`: the GNU-direction case, the neither-form case and the ratchet
all go **red**; the BSD-direction case is green on both sides **by design**, since its job is to prove
the fix did not break the platform that already worked.

## What this does NOT settle

- **The other ~50 sites of this class are untouched**, deliberately. `land-lock.sh` is the one the
  census convicted, with a driven failure on the land path this plan is about. The rest are named by
  `hooks/lib/mailbox-pending.sh`'s grep and remain unfiled work; widening to them here would be a
  refactor riding a measurement that covers one file.
- **It says nothing about the producer's own red list.** Every claim here is about a Linux VM. The
  causes for the reds `macos-latest` actually reports (`operator-readout` 43, `ship-land` 17,
  `qos-rewrite` 13, `cc-reaper` 51) are still unmeasured, and the manifest still wants them measured
  **there**.
- **It does not move `d84434cd`.** The cloud land arm's discriminator still needs the three reads that
  exist only on the operator's box (`scripts/cloud-land-arm-diagnose.sh`); `f85fce7c26f5` stays
  operator-gated on them.
- **`test-hermeticity-lint`'s 441 s is a number from this box.** If the producer overruns its bound on
  it, that is a cost exclusion someone must measure on the producer before writing the line.
