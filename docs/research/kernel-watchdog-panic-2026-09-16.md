# Kernel watchdog panic, 2026-09-16 — the whole kitty fleet died at once

**Status:** OPEN — evidence captured by the recovery session, analysis and prevention design NOT started.
**Owner:** the research session fired from this doc.
**Artifact:** `/Library/Logs/DiagnosticReports/panic-full-2026-09-16-155400.0002.panic` (4.5 MB, JSON;
a copy rides beside this doc as `panic-2026-09-16.panic.copy`, untracked).

## Scope (frozen)

Answer, from disk truth, WHY this box hard-panicked, and land a prevention design that makes the
same wedge either impossible or self-limiting. Two deliverables, both required:

1. **A diagnosis** naming the mechanism, with a `file:line`/field citation for every claim, and
   explicitly separating what the panic log PROVES from what it merely permits.
2. **A prevention design** — bounded, implementable in this repo, with the acceptance test that
   would show it works. Landing the implementation is IN scope if the design is settled and green.

## What is already established (do not re-derive; DO re-verify anything you rely on)

Anchors:
- Panic at **2026-09-16 15:54:00 -0500**; reboot at **15:50:58**. macOS 15.7.9 (24G830),
  MacBookPro18,2 (M1 Pro/Max, T6000), **64 GB** RAM, kernel `xnu-11417.140.69.711.44`.
- Previous reboot was **2026-08-25** — 22 days clean. This is NOT a recurring panic; there is
  exactly one `.panic` file on the box.

The panic string:

```
panic(cpu 2 caller 0xfffffe002b6b434c): watchdog timeout: no checkins from watchdogd
in 91 seconds (26079 total checkins since monitoring last enabled)
```

`AppleARMWatchdogTimer` fired because `watchdogd` could not be scheduled for 91 s. That is a
SYMPTOM of a system-wide wedge, not a cause — the cause is whatever starved it.

**Memory state at panic** (`memoryStatus`, pageSize 16384):

| field | pages | bytes |
|---|---|---|
| wired | 1,324,927 | **20.22 GB** |
| active | 550,132 | 8.39 GB |
| inactive | 550,086 | 8.39 GB |
| **free** | **906** | **14.8 MB** |

- `memoryPressureDetails`: **pagesWanted 3094, pagesReclaimed 52** → **1.7 % reclaim efficiency**.
  The pageout path was asking and getting nothing.
- `memoryPressure: false` — the kernel's own pressure flag read FALSE while reclaim was failing 98 %
  of the time. That discrepancy is itself a finding worth running down.
- `compressions: 352,601,482` / `decompressions: 257,553,952`; compressor size 1,645,483 pages.
- 20.2 GB WIRED on a 64 GB box is abnormal (normal here is single-digit GB). Wired is unswappable,
  so it is the term that can actually strangle reclaim. **Whose wired pages?** — unanswered.

**The blocking chain** (`processByPid`):

```
pid 0 kernel_task  thread 2298: kernel mutex 0xfffffe000c294940 owned by thread 101
                   turnstile: blocked on 101, hops: 1, priority 91
```

**680 of 1,032 processes carried a `waitInfo`** — most are ordinary `mach_msg receive` idles, so do
NOT read 680 as "680 hung tasks" without separating idle-receive from genuine blocking.

**Process census — 1,032 processes.** Top names:

| n | proc | n | proc | n | proc |
|---|---|---|---|---|---|
| 175 | xpcproxy | 123 | bash | 48 | zsh |
| 38 | sh | 31 | gitstatusd | 29 | Browser Helper (Renderer) |
| 24 | node | 23 | claude.exe | 22 | Python |
| 22 | ps | 19 | distnoted | 16 | tee |
| 13 | jq | 12 | Cursor Helper (Plugin) | 11 | login |

**This is overwhelmingly our own fleet.** 23 `claude.exe` + 24 node + 123 bash + 48 zsh + 38 sh +
31 gitstatusd + 22 ps + 16 tee + 13 jq is the hook/sweep/gate/session-shell layer of this repo,
not the OS. 175 `xpcproxy` is the spawn-storm signature (xpcproxy is the exec stub for a launchd
job — a high count means jobs being spawned faster than they exec).

`last started kext: com.apple.filesystems.smbfs` — an SMB mount is a classic kernel-wedge source.
Whether one was mounted, and whether it is on the mutex chain, is UNTESTED.

## Open questions — these are the work, not a list to file

1. **Who owned thread 101?** Resolve the mutex owner. `binaryImages` + the kext load list are in the
   same JSON. If it is `smbfs`, the story is a network-filesystem stall; if it is the VM/compressor,
   the story is memory. These imply different fixes.
2. **Which subsystem holds 20.2 GB wired?** The panic log may not answer it; if not, say so and
   design the instrument that WOULD (a wired-memory sampler is cheap and we have none).
3. **Is `memoryPressure: false` with 1.7 % reclaim a kernel bug, a definitional artifact, or our
   misreading?** It matters because every jetsam/pressure-based guard we might build keys on that flag.
4. **Did our fleet CAUSE it, CONTRIBUTE to it, or merely die with it?** Be honest about which the
   evidence supports. 1,032 processes is a fact; "1,032 processes panicked the box" is a hypothesis,
   and the corpus rule is that a mechanism must be priced in the units of the observed cost before
   it is accepted (see `.claude/rules/agent-operating-lessons.md`, "price a proposed cause").
5. **What is the fleet's steady-state process count, and what is its ceiling?** Nothing on this box
   measures or bounds it. `hooks/`, `scripts/autonomy-sweep.sh`, `cc-reaper`, the postland lane and
   the per-session shells all spawn; no admission gate counts TOTAL processes.
6. **Prevention.** Candidates, none yet argued: a process-count admission gate; a wired-memory
   watchdog that sheds sessions before the kernel watchdog fires; bounding concurrent sessions;
   bounding hook fan-out; a pre-panic tripwire that at least LEAVES A RECORD (we got none —
   the first thing anyone knew was a black screen).

## Method constraints (this repo's corpus, and they bind)

- **Every claim needs a citation** — a panic-log field, a `file:line`, or a command you ran and
  printed. A mechanism that cannot reach the observed magnitude is not a candidate.
- **A one-armed search cannot acquit.** If you look for evidence that our fleet caused this, also
  run the arm that could refute it.
- **Write incrementally.** Append to this doc as each question resolves — do not hold the findings
  and write at the end. (A prior session lost a full editing pass to a turn cap doing exactly that.)
- **Do not commit in `~/Development/claude-infrastructure`** — it is the shared checkout and the
  symlink source for `~/.claude`. You are in a dedicated worktree; commit here, land via the
  project-local `/ship`.
- The 6 recovered sessions are LIVE in other panes and were deliberately NOT nudged. Do not send
  them keystrokes, and do not `kill`/`pkill` anything broadly — an empty selector on this box has
  already caused a mass-termination incident (see the corpus rule of that name).

## Status log

- **2026-09-16 (recovery session):** panic anchored, memory + census + blocking chain extracted,
  6 crashed sessions restored unnudged. Analysis not started. This doc created; nothing implemented.
