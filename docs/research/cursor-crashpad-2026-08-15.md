# The Cursor crashpad loop: three findings from trunk, and the venue gap that stopped the fourth

**2026-08-15.** Backlog item `e020ebb2b8c7` — *"Cursor `chrome_crashpad_handler` crash-loop ~5/s
while Cursor runs (chronic since ≥08-12): diagnose on next Cursor launch — spindump the handler,
check version currency, reinstall if current"* — was dispatched to a `--venue cloud` session. The
work is a live macOS app's crash loop: it needs `spindump`, `~/Library/Logs/DiagnosticReports`,
`/Applications/Cursor.app`, and Cursor actually running. **None of that exists in a Linux microVM,
so the item is not adjudicated and cannot be from here.**

What *could* be done from here was done: the item's own DoD ref and its sibling incident doc carry
evidence the item's brief never inherited, and reading them **corrects the item's stated method
before anyone spends a local slot on it**. Three findings below, then the venue measurement.

---

## 1. What trunk already knows that the item's brief does not

The item's brief carries the wedge doc's §4 summary. The *other* incident doc from the same night
carries the discriminator, and nothing joined them:

| Fact | Source |
|---|---|
| Owner is Cursor: `.ips procPath` = Cursor.app's Electron Framework helper, `responsible: Cursor` | `wedge-2026-08-13.md` §3, §4 |
| **Signature: identical `EXC_BREAKPOINT` / `SIGTRAP` across all 124 reports on 08-13** | `freeze-2026-08-13.md` § *Chronic pathologies* |
| Rate ~5/s while Cursor runs — 598 crashes/2 min at the 20:00 control, 47 in the final 90 s; **50 `.ips` at 17:0x, ReportCrash throttled after** | `wedge-2026-08-13.md` §3 |
| Crashpad DB clean (`settings.dat` only) ⇒ the corrupt-database class is out | `wedge-2026-08-13.md` §4 |
| **Cursor's ShipIt updater was live-patching a running Electron app 41–99 s before the bursts**; its `PreventSystemSleep "Updating"` assertion timed out 21:21:58 | `freeze-2026-08-13.md` |
| Real cost: ReportCrash + diagnosticservicesd among the top log producers all evening; `osanalyticshelper: Log limit exceeded` | both |

## 2. Finding A — the "two bursts" reading is a throttling artifact, and the wedge doc refutes it

`freeze-2026-08-13.md` reads *"124 reports today in two bursts (Aug 12 23:23–23:40, Aug 13
17:00–17:14)"*. `wedge-2026-08-13.md` measures **598 crashes/2 min at a 20:00 control** — after the
second burst closed — and states outright that ReportCrash **throttled** after 50 `.ips` at 17:0x.

Both are right about what they measured. The **reports** are bursty; the **crashes** are not. The
burst boundaries are ReportCrash's write throttle, not the loop starting and stopping.

Why this changes the method: a live capture planned around "wait for a burst" is waiting for an
artifact of the reporter. **Launch Cursor and the loop is there** — that is what ~5/s continuous
means, and it is what makes this cheap to catch.

## 3. Finding B — `spindump` is the wrong instrument, and the right one already exists in quantity

`EXC_BREAKPOINT` / `SIGTRAP` is a **deliberate** trap, not a fault. Chromium's and Crashpad's
`CHECK()` compiles through `IMMEDIATE_CRASH()` → `__builtin_trap()` → `brk #0` on arm64, and that
is exactly how a failed internal invariant surfaces in an `.ips`. *(Inference from the signature,
not a measurement — falsifiable by reading one report, which is the point.)*

So the handler is neither hung nor slow. It aborts at a known source line within milliseconds of
`exec`, about five times a second. **`spindump` samples live processes over an interval** — against
a process whose entire lifetime is shorter than a sample tick, it is a lottery, and a system-wide
spindump would show little more than the respawn cadence already measured.

The instrument that carries the answer is the one already writing to disk: each `.ips` holds the
faulting thread's backtrace, naming the failing check. There are **≥124 of them from 08-13 alone**,
and they need no live Cursor to read.

**Read one `.ips` first. Reach for `spindump` only if its backtrace comes back unsymbolicated.**

## 4. Finding C — the signature excludes three suspects, and leaves one falsifiable fork

`SIGTRAP` is discriminating, and it rules out the usual candidates before anyone touches the
machine:

- **Not a code-signing kill.** That is `SIGKILL` with a `CODESIGNING` termination reason, never
  `SIGTRAP`. Any quarantine / translocation / partial-bundle-swap story must therefore show up as a
  *failed check*, not as a kill.
- **Not memory pressure.** Jetsam presents as `EXC_RESOURCE` or a jetsam kill — independently
  consistent with the wedge doc's §2 exoneration of the storm class.
- **Not a corrupt-DB read fault.** That would be `EXC_BAD_ACCESS`, and it agrees with the
  already-observed clean Crashpad DB rather than resting on it.

What remains is a Crashpad-internal invariant failing at startup. The ShipIt correlate makes one
hypothesis leading and, usefully, **testable in one command**:

> **H:** Cursor's in-place update replaced the app bundle under the *running* instance, so the
> running app keeps re-spawning a handler out of a bundle that is no longer the one it launched
> from, and the handler checks-and-traps every time.

**H predicts** the loop dies on a plain relaunch of the current bundle and does not need a
reinstall. **H is refuted** if the loop is present immediately on a fresh launch — in which case
this is a plain version bug, and public reports raise that prior: `chrome_crashpad_handler` crash
loops are actively reported against Cursor on macOS through 2026 by users other than this operator.
*(Search-result titles and snippets only — `forum.cursor.com` is blocked by this VM's egress proxy,
so no primary source was read. Treat as a prior, not as evidence.)*

That prior also sharpens the item's own last clause. **"Reinstall if current" is a trap if the
current version is the one with the bug** — reinstalling it changes nothing. Version currency has
to be resolved against the changelog, not against "am I on latest".

## 5. The sharpened local brief

Cheapest-first, and the first two need no live Cursor at all:

```sh
# 1. What actually failed — the backtrace the spindump was meant to approximate.
f=$(ls -t ~/Library/Logs/DiagnosticReports/chrome_crashpad_handler-*.ips | head -1)
tail -n +2 "$f" | jq '{exception, termination, faultingThread}'
tail -n +2 "$f" | jq '.threads[.faultingThread]'

# 2. Test H before spending anything — was the bundle replaced under the running app?
#    bundle mtime NEWER than the process start ⇒ H holds ⇒ relaunch Cursor, done, no reinstall.
stat -f '%Sm bundle' -t '%F %T' /Applications/Cursor.app
ps -o lstart= -p "$(pgrep -x Cursor | head -1)"

# 3. Only if H is refuted: version currency against the changelog, not against "latest".
defaults read /Applications/Cursor.app/Contents/Info.plist CFBundleShortVersionString
```

Reinstall is step 4, and only if 1–3 leave it warranted.

## 6. The venue measurement — a second face of the 08-14 gap, and the proposed fix misses it

`docs/research/venue-foreign-project-repo-2026-08-14.md` recorded a cloud dispatch of work whose
**project was not the repo a cloud fire attaches**, and proposed a desk-side fix: one comparison
(item's project vs the attached repo) behind a refusal token `ineligible-foreign-repo`.

**That fix would not have caught this item.** Here the project *is* `claude-infrastructure`, the
attached repo, and the comparison passes. The classifier itself is wrong. Measured from inside the
misrouted session, against a fixture row carrying the item's text:

```
$ cc-eligible why <row> --json
  "verdict": "eligible",
  "description": "repo-only work — no local-only state named",
  "tokens": [],
  "classes": [],
  "history": { "state": "no-repo", "depth": 50 }
```

The `BOX` list's scope statement already covers this item exactly — *"state that exists only in
this kernel, this filesystem, … or this window server"*. It is the **spellings** that are absent.
Per this file's standing duty (*"the sweep is the instrument for finding what this list does not
say … ADD the spelling you find"*), the ones this item used and the list lacks:

| Spelling | Why it is box state |
|---|---|
| `spindump` | a Darwin sampling tool, against this process table |
| `.ips` / `ReportCrash` / `DiagnosticReports` | crash reports on this disk, written by this OS |
| `crash-loop` / `crashes/s` | an observed rate of a process on this box |
| `reinstall` | an app in `/Applications` on this filesystem |
| `Cursor` (and app names generally) | a GUI app installed here, whose live state is the subject |

Note the list already carries `macos` / `darwin` — the item's text simply never says either word.
That is the shape of the miss: not a gap in scope, a gap in vocabulary, which is what the file's own
header warns a denylist always is.

**Ledger and comms are equally unreachable from here**, measured:

```
$ cc-backlog venue e020ebb2b8c7 --venue local --why …   → cc-backlog venue: unknown id e020ebb2b8c7
$ cc-backlog reopen e020ebb2b8c7                        → cc-backlog reopen: unknown id e020ebb2b8c7
$ cc-notify --role desk …                               → verdict=unresolvable reason=role-unset
```

`~/.claude/autonomy/` is empty in this VM. Trunk is the only store a cloud dispatch can reach, which
is why this file is the deliverable and not a ledger row.

## 7. Not fixed here, deliberately

`bin/cc-eligible` is **not touched**, on the same guard the 08-14 doc stopped at: a cloud VM must not
build or run the venue rule — it would be deciding its own admission, and its clone cannot read the
history that justifies the exclusions. This session is that VM (`git rev-list --count HEAD` → 50,
`.git/shallow` present). Writing the spelling additions from here is the thing the guard forbids;
recording them is not.

## 8. The item itself

`e020ebb2b8c7` is **NOT adjudicated**. No claim above touches whether the loop is still occurring,
what the failing check is, or which version is installed — all three need the desk. What the item
has gained is a corrected method (§3), a wrong turn removed (§2), three excluded classes and one
testable hypothesis (§4), and a cheapest-first brief (§5).

It needs a **local** claim, with Cursor running. Desk-side, in order:

```sh
cc-backlog venue  e020ebb2b8c7 --venue local \
    --why "box-local: spindump/.ips/Cursor.app — no off-box instrument; see docs/research/cursor-crashpad-2026-08-15.md"
cc-backlog reopen e020ebb2b8c7
```
