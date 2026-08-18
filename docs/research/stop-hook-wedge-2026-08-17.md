# Stop-hook wedge (backlog `50627335fe9b`) — the frame the row keys on does not exist

**Date:** 2026-08-17 · **Row:** `50627335fe9b` (open, condition `master-session-lifecycle`,
source `resume-sessions-2026-08-10`, firstTs 2026-08-11T03:50Z)

> Row, verbatim: *"Stop-hook chain wedges at 12/13 with no live child and never self-recovers —
> measured 54min on pane 113 (ff519bfd): advancing hook timer + ZERO hook children = harness blocked
> on a pipe whose writer is gone; every liveness proxy reads 'working'; only a human Escape
> recovered it. Want: which hook is #12 in the settings.json Stop order, why it exits without
> closing its pipe, and a detector keyed on the CONJUNCTION (hook frame displayed AND no hook child)
> since neither half alone is a fault."*

**Verdict: the row's diagnosis of the MECHANISM is corroborated by code; its prescribed DETECTOR is
not buildable as specified, because the first conjunct — a displayed hook-progress frame carrying a
`12/13` fraction — is not something the binary this fleet runs ever renders.** Ask 1 is
EVIDENCE-EXPIRED. Ask 2 is answerable from present-day code and points at Stop hook **#1**, not #12.
Ask 3 must be re-specified before anything is built.

---

## 1. Two-question pass

### (a) Did the remedy already land? — NO

```
git log -S'hook-frame'     origin/main -- hooks/ scripts/ bin/ tests/   → 0
git log -S'no-hook-child'  origin/main -- hooks/ scripts/ bin/ tests/   → 0
git log -S'stop-hook-wedge' origin/main -- hooks/ scripts/ bin/ tests/  → 0
grep -rln 'hook.*frame|hookFrame|hook_frame' hooks/ scripts/ bin/ tests/ → (empty)
```

`bin/cc-wedge-watch` exists and is the nearest neighbour, but it is a **different defect**: a
one-shot, launch-time check that a *newly spawned* pane produced an assistant turn (startup-modal
wedge). It is armed from `bin/cc-pane-runner` with a `--timeout` and never re-arms, so it cannot see
a mid-session Stop-chain wedge at all. Verified by content, not by subject.

### (b) Does the row's evidence still exist? — NO. **EVIDENCE-EXPIRED**, and by an unusual mechanism.

The transcript of session `ff519bfd-00d4-4991-a099-d3aef01352d7` is gone:

```
find ~/.claude/projects ~/.claude-secondary/projects -name '*.jsonl' \
  | xargs -n1 basename | grep -c ff519bfd   → 0
```

It did not merely age out of a retention window. A surviving artifact names the file's original
home:

```
~/.claude/autonomy/postland/wt-run-51167/docs/research/context-economy-100p-2026-08-11/announced-not-fired.md
  → "Source: ~/.claude/logs/handoffs.jsonl vs ~/.claude-quaternary/projects/.../{ff519bfd,8f478e5c}*.jsonl"
```

**The session lived in `~/.claude-quaternary`, and that entire config dir no longer exists on this
box.** Only `~/.claude`, `~/.claude-secondary` and `~/.claude-next` survive. So the loss is not
retention decay — a whole account home was removed, taking its transcripts, its `settings.json`, and
therefore the roster the row's `12/13` was counted against.

What *does* survive, and is all that survives:

| Artifact | Content |
|---|---|
| `~/.claude/cc-beats/ff519bfd-….json` | `pane 113 · cwd /Users/chrisren/Development/claude-infrastructure · pid 73196 · lstart Mon 10 Aug 18:15:43 2026 · last beat kind:"prompt" who:"auto" seq 27` |
| `~/.claude/autonomy/comms-alarms/undelivered-20260811T031346Z-35177-8543.json` | `"1 message(s) unconsumed 8190s AND owner liveness INDETERMINATE (it2 unreadable) — cannot prove delivery"` @ 2026-08-11T03:13:46Z |
| `~/.claude/mailbox/ff519bfd-….{md,seen,acked,watching,posttool}` | mailbox markers only |

The `undelivered` alarm is worth keeping: it is an **independent corroboration that the session was
unresponsive for a long window** (8190 s ≈ 2 h 16 m of unconsumed mail with liveness indeterminate),
recorded by a different mechanism than the one the row describes. It says nothing about *which* hook.

---

## 2. Ask 1 — "which hook is #12 in the Stop order": **EVIDENCE-EXPIRED, not determinable**

### The merge surface, measured

Claude Code composes the Stop chain from: managed settings → the **user config dir**'s
`settings.json` → project `.claude/settings.json` → project `.claude/settings.local.json`.

- Managed settings: **absent** (`/Library/Application Support/ClaudeCode/managed-settings.json` does
  not exist).
- Project `.claude/settings.json` and `.claude/settings.local.json` in this repo declare **zero**
  Stop hooks — today, and at every commit spanning the incident (`7436a3a65` 2026-08-08,
  `ff49e1e36` 2026-08-11, `86e354262` 2026-08-12, all `Stop entries: 0`).

**Therefore the entire Stop chain came from one file: the user config dir's `settings.json` — which
for this session was `~/.claude-quaternary/settings.json`, and that file is gone with its dir.**

The "FIVE separate real files" of sibling row `adf1bb6b5406` are the five *config dirs*, confirmed by
the only surviving multi-dir snapshot (`~/.claude/backups/settings-recap-20260805-132642/`):
`.claude`, `.claude-next`, `.claude-secondary`, `.claude-tertiary`, `.claude-quaternary`.

### Why the index cannot be recovered

| Source | Stop entries | Date |
|---|---|---|
| `settings-recap-20260805/.claude-quaternary.settings.json` (**the session's own dir**) | **11** | 2026-08-05, five days pre-incident |
| `settings-recap-20260805/.claude.settings.json` · `.claude-secondary` · `.claude-tertiary` | 11 | 2026-08-05 |
| `settings-recap-20260805/.claude-next.settings.json` | 10 | 2026-08-05 |
| `~/.claude/settings.json` · `~/.claude-secondary/settings.json` (live today) | **12** | 2026-08-17 |
| `~/.claude-next/settings.json` (live today) | 11 | 2026-08-17 |
| `settings-templates/settings.example.json` (the tracked mirror) | 9 | tracked, and diverged from every live file |

**No snapshot anywhere reaches 13.** The live `settings.json` files are real untracked files (not
symlinks into this repo), so they have no git history; the tracked template has drifted to 9 and is
not the executed artifact. There is no backup between 2026-08-07 and 2026-08-17.

### Best reconstruction, stated as a reconstruction

`hooks/goal-inert-watch.sh` landed 2026-08-09 (`735a2466a`), one day before the session started, and
sits at index 11 in today's `~/.claude` roster. Row `11fdba2b3148` independently records that
`ff519bfd` was **goal-armed**, and `/goal` injects its own Stop hook. So `11 (Aug-5 quaternary) + 1
(goal-inert-watch, if the mirror reached the forked quaternary) + 1 (the /goal-injected hook) = 13`,
which would put **#12 = `~/.claude/hooks/cc-permission-beacon.sh clear`** (the last static entry) and
**#13 = the /goal-injected Stop hook**.

**Do not act on that.** Three links in it are unverifiable and each breaks it: whether the
`goal-inert-watch` merge ever reached `~/.claude-quaternary` (row `adf1bb6b5406` records that the
config mirror *refuses to touch a forked dir*, and quaternary was one of the forked ones); whether
`/goal` appends its hook last or first; and whether the frame counts hooks the way the arithmetic
assumes. And §4 below shows the frame it assumes does not exist.

**`cc-permission-beacon.sh` is in any case exonerated as the pipe-holder**: it contains no `&`, no
`nohup`, no `setsid`, no `disown`. It cannot leave a writer behind.

---

## 3. Ask 2 — "why does it exit without closing its pipe": answerable from code, and it indicts **#1**

The row's mechanism claim holds up, and one more measurement sharpens it.

**Every Stop hook in the live chain carries a 5–10 s timeout** (`~/.claude/settings.json`):

```
notify.sh complete 5 · cache-expiry-tracker 5 · teammate-checkpoint 10 · session-continue 5
anti-deference-nudge 5 · completion-assert 5 · dispatch-assert 10 · boundary-handoff 5
operator-readout 10 · session-beat 5 · goal-inert-watch 5 · cc-permission-beacon 5
```

Worst case for the whole chain is ~75 s. **The observed wedge was 54 minutes — 43× the sum of every
timeout in the chain.** So the wedge is provably *not* "a hook running long": the harness's own
timeouts bound that. The only shape consistent with both facts is the row's: the timeout kills the
hook **process**, but the harness's read on that hook's stdout does not return EOF, because a
**backgrounded descendant still holds the write end of the pipe**. That is
memory `procsub-pid-is-unreachable-own-the-pipe` (43 wrappers pinned 10 h by one orphan's fd 2) —
cited in `bin/cc-wedge-watch`'s own header, and now recurring on the Stop path.

### Census: which Stop hooks background a child at all

Scanning all twelve for `&` / `nohup` / `setsid` / `disown`, exactly two do:

| Hook | Site | Child's fd 1 | Child's fd 2 |
|---|---|---|---|
| `session-beat.sh` (#10) | `beat "${1:-prompt}" >/dev/null 2>&1 &`  ·  `( sleep "$P8_TIMEOUT"; kill -9 "$_w" ) >/dev/null 2>&1 &` | `/dev/null` ✅ | `/dev/null` ✅ |
| **`notify.sh` (#1)** | `afplay "${SOUND}" 2>> "$NTY_LOG" &` then `disown` | **INHERITED — the harness's pipe** ❌ | log file ✅ |

`hooks/notify.sh:288-296`. The author reasoned explicitly about the child's **stderr** — the comment
reads *"afplay's stderr is the OTHER append at this path — a redirect the eye skips"* — and left
**stdout inherited**. `disown` removes the job from the shell's job table; it does not close a file
descriptor. So `afplay` outlives `notify.sh` (which exits immediately, by design) while still holding
the write end of `notify.sh`'s stdout pipe.

This reproduces every observed symptom without needing the expired transcript:

- **advancing hook timer** — the harness is still blocked on `read`, so its elapsed counter climbs;
- **ZERO hook children** — `notify.sh` is dead (timed out at 5 s); `afplay` is not a hook script, so
  any census that looks for *hook* children misses the actual pipe-holder entirely;
- **never self-recovers** — the per-hook timeout has already fired and did not help; nothing else in
  the chain closes that fd;
- **only a human Escape recovered it** — cancelling the turn tears down the read.

**Caveat, stated plainly:** this is a mechanism that *fits*, established from present-day code, not a
replay of the 2026-08-10 event — that evidence is gone (§1b). A short chime exits in under 2 s and
leaks nothing, which is why this is rare rather than constant; the hang case is `afplay` blocking on
a busy or disconnected audio device. **No lingering `afplay` exists on the box right now**
(`pgrep -x afplay` → empty), consistent with a rare fault, and consistent with the row having
measured it exactly once.

---

## 4. Ask 3 — the detector: **the prescribed first conjunct does not exist**

The row asks for a detector on *hook frame displayed* **AND** *no hook child*. The second conjunct is
cheap. The first was measured against the renderer, and it is not there.

Binary: `~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (Mach-O arm64,
256 MB, the build every live pane on this box is executing — `ps -eo comm` → all sessions run
`~/.claude-220/node_modules/.bin/claude`). Extracted with `strings -a` (652,094 lines).

**The only hook frame this binary renders is past-tense and has no total:**

```js
const GTn = k4t === 1 ? "hook" : "hooks";
x4t = uo.jsxs(h, {dimColor:!0, children:[WTn, "Ran ", k4t, " ", f4e.hookLabel, " ", GTn, ""]})
// and the sibling branch:
Wma = uo.jsxs(h, {children:["Ran ", Lyt, " ", VTn, " ", sGp, "", jma]})   // VTn = f4e.hookLabel ?? "stop"
```

i.e. **`Ran <N> <Label> hooks`** — rendered *after* the hooks complete, with a single count and **no
denominator**. The supporting state confirms it is post-hoc accounting, not in-flight progress:
`hookCount`, `hookTotalMs`, `hookInfos` are initialised to `0/0/[]` and written only under
`if (e.hookCount > 0)` when assembling the finished summary.

Searches that returned **zero** hits across all 652,094 strings: `hooksRunning`, `runningHooks`,
`pendingHooks`, `hookProgress`, `Running …hook`, `hooks…`. There is no in-flight counter, no total,
and no `N/M` fraction anywhere in the hook render path.

**Conclusion: `12/13` is not a literal this renderer emits.** It is either a paraphrase of a spinner
the observer read as a fraction, or a frame from a different build. Either way, **keying axis A on a
hook-progress fraction would ship a detector anchored on a string measured absent from the
production renderer** — the exact defect `bin/cc-wedge-watch`'s header was written to record
(`?forshortcuts`: prescribed as "9/9 across every probe", re-measured four days later at **0 of 23**
healthy panes; shipped as prescribed, its first act would have been to page 23 healthy panes).

### Why the conjunction was load-bearing, and what it costs to lose it

The row is right that neither half alone is a fault, and it is right for a reason that survives the
refutation:

- *no hook child* alone is true of **every** healthy session at almost every instant — hooks run in
  milliseconds. Alone it is an alarm that fires continuously.
- *transcript frozen + process alive* — the obvious disk-only substitute — is exactly the state of a
  session **idling at the composer waiting for the operator**, which is healthy. `bin/cc-wedge-watch`
  measured this directly: *"transcript absence does not discriminate — 0 `*.jsonl` in BOTH the
  stalled and the cleared home."*

So the frame was doing the entire discriminating job, and there is **no disk-only substitute for
it**. That is why this cannot be re-specified as a cheap screen-free poll, and why nothing is shipped
here.

### What to build instead — a static lint, not a runtime alarm

The §3 census generalises into a check with none of the above problems: **no TUI literal, no
attention budget, deterministic, and it fires on a real present-day defect.**

> **Predicate:** for every hook registered in any `settings.json` on this box, any command that
> backgrounds a child (`&`, `nohup`, `setsid`) must redirect that child's **stdout** (and stderr)
> away from the inherited descriptor. A backgrounded child that inherits fd 1 can outlive the hook
> and hold the harness's read pipe open past every timeout.

Expected fire rate today: **1** — `hooks/notify.sh:292,294`. `session-beat.sh` is the built-in
positive control for the compliant side (both fds redirected), so the lint's own denominator is
policed and it can be shown to fail as well as pass. This is a `scripts/*-lint.sh` in the shape of
the existing `unattended-path-lint.sh` / `alarm-polarity-lint.sh`, gated at the chokepoint that
already runs them.

**Not built here** — the session hit its stop threshold at the point the refutation landed, and
building a *runtime* alarm on a refuted anchor was the thing the brief forbade. The lint is a
different artifact from the one the row asks for and should be filed as its own row rather than
smuggled in under this one.

---

## 5. Recommended row disposition

`50627335fe9b` should **not** be closed as done, and should not stay open as written — as written it
asks for something unbuildable, so it will keep minting duplicate analysis
(memory: `refuted-open-row-remints-its-own-analysis`). Suggested split:

1. **Close this row as REFUTED-AS-SPECIFIED**, pointing at this file: ask 1 is EVIDENCE-EXPIRED
   (config dir deleted), ask 2 is answered (§3), ask 3's anchor does not exist (§4).
2. **Open**: *"hook backgrounding lint — a Stop/any-event hook whose backgrounded child inherits
   fd 1 can hold the harness's read pipe open past every timeout; 1 live instance
   (`hooks/notify.sh:292,294`), positive control `hooks/session-beat.sh:113,115`."*
3. **Consider** (separate, cheap, no lint needed): redirect `afplay`'s stdout in `hooks/notify.sh`.
   That is a one-character-class change to the live layer and belongs to whoever owns that hook.

## 6. Reusable lessons

- **A prescribed screen anchor is a claim about a renderer, and it must be measured against the
  renderer that is actually executing.** Second recurrence in this repo after `?forshortcuts`. The
  binary is greppable; grep it before building.
- **A wedge far longer than the sum of the configured timeouts is not a slow child — it is an fd the
  timeout cannot reach.** The timeout kills a *process*; only closing a *descriptor* ends a read.
- **A "no hook child" census is blind to the process that actually holds the pipe**, because the
  pipe-holder is a grandchild that is not a hook. Key on the descriptor, not on the process class.
- **An account home's deletion expires evidence far faster than any retention policy**, and it takes
  the `settings.json` that indexes the incident with it. Untracked live config has no history to fall
  back on.
