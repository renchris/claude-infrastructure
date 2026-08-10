# 11 · Prior art + legitimate platform levers for dense agent fleets on Apple Silicon

**Scope**: what other operators of many-process macOS workloads do that this program has not tried.
**Box**: M1 Max (10 cores: 8P/2E), 64 GB, macOS **15.6.1 (24G90)**, SIP **enabled**, no hardware purchase.
**Measured here** = first-party measurement taken in this session on this box (2026-08-09, load 21–24
unless noted). All timings are conservative: they were taken on a loaded box, and the dominant term
is single-threaded, so a busier box is worse, never better.

**Do-not-relitigate** (settled in `docs/plans/CONCURRENCY_PROGRAM.md` §S6.8, read read-only from
`/Users/chrisren/Development/.worktrees/scale-150`): 150 simultaneously-ACTIVE sessions · 150 resident
with unbounded toolchain bursts · Spotlight/worktree exclusion (dot-dirs already unindexed, 0 files) ·
`taskpolicy -c background` (84–89× tax). Nothing below re-opens any of these.

**Evidence quality flags**: `[VENDOR]` vendor/first-party doc · `[EXPERT]` recognised independent
analyst · `[MEASURED]` measured here this session · `[FORUM-DTS]` Apple DTS engineer on the developer
forums · `[OSS]` open-source repo/issue/PR · `[ANECDOTE]` blog/community claim, unreplicated.

---

## 0 · Headline

**The exec-assessment tax has a call-convention remedy that costs nothing and changes no setting.**
Measured on this box: `./script.sh` on a novel file = **~121 ms**; `bash ./script.sh` on an equally
novel file = **~2.9 ms**. A **40×** difference, from moving the file out of the `execve()` path.
Everything else in this dossier is smaller.

---

## A · Exec-assessment reduction (XProtect / Gatekeeper / syspolicyd)

### A.0 The mechanism, measured end to end

| Fact | Measured value | Method |
|---|---|---|
| Novel shell script, `./script` (execve + shebang) | **121–213 ms** first exec; **2.6–3.5 ms** thereafter | 20-script serial run, ΣLAT 3 215.8 ms ⇒ **160.8 ms mean** |
| Same script, second exec | 2.8 ms | same |
| Novel script invoked `bash ./script` | **2.7–3.2 ms** | 3 paired novel files |
| Novel `.py`, `./file` vs `python3 file` | **155–168 ms** vs **27–39 ms** | 2 paired novel files |
| Copy of an **Apple-signed** Mach-O (`cp /bin/echo x`) | **0.0 ms** — no tax at all | 5 copies |
| Freshly **clang-compiled** Mach-O (ad-hoc / linker-signed) | **119–170 ms** — *pays in full* | 3 binaries, `codesign -dvvv` = `flags=0x20002(adhoc,linker-signed)` |
| Mach-O with a **broken** signature | 1.3 ms then **SIGKILL (exit 137)** — AMFI kills before any scan | 1 binary |
| Cache key | **(device, inode)** — NOT content | identical bytes at a new path = **169 ms**; `cp` of an assessed file = **248 ms**; **hardlink** of an assessed file = **4.1 ms** |
| In-place mutation of an assessed file | **3.5 ms** — does *not* re-trigger | append then exec |
| `git checkout` re-materialising a script | **136.5 ms** — git writes a new inode ⇒ full re-tax | init/commit/rm/checkout |
| Owning daemon | **`XprotectService`** — `TIME` +3.03 s across a 2.85 s wall; `syspolicyd` +0.31 s; `amfid` +0.00 s | `ps -Ao time` before/after |
| Parallelism | **serialises** — 8-way = 118.9 ms/file vs serial 127.3 ms/file (**7 %** gain) | 24 novel files each way |

⇒ The tax is a **single-threaded, per-inode, first-exec XProtect scan**, and *only a signature the
system already trusts* escapes it. Ad-hoc signing does **not**; a Developer-ID-notarized signature
plausibly does (see A.3) but the round-trip is per-build and impractical for a fleet's own scripts.

This independently reproduces the mechanism the Rust toolchain community documented, and it is the
direct explanation for the program's own "`XprotectService` 31 % mean CPU at ~15 sessions".

### A.1 Lever table

| lever | applies-here | evidence (quality) | command/config | confidence |
|---|---|---|---|---|
| **Invoke scripts through the interpreter, not `execve`** — `bash x.sh` / `python3 x.py`, never `./x.sh` | **Y** | `[MEASURED]` 121 ms → 2.9 ms (bash), 160 ms → 33 ms (python) | Hook `command` strings: `bash ~/.claude/hooks/foo.sh` not `~/.claude/hooks/foo.sh`. Generated/temp scripts: always call the interpreter | **High** |
| **Never `cp` a script that a hardlink would do** — hardlinks share the assessment; copies do not | **Y** | `[MEASURED]` hardlink 4.1 ms vs copy 132–248 ms | `ln src dst` (pnpm's store already gets this for free) | **High** |
| **Keep `~/.claude/{hooks,bin,scripts}` as per-file symlinks into ONE checkout** | **Y — already true, and it is load-bearing** | `[MEASURED]` `ls -l ~/.claude/hooks/` = symlinks to `claude-infrastructure/hooks/`; hardlink/symlink ⇒ one inode ⇒ **assessed once box-wide** | keep it; a future "copy hooks per worktree" refactor would silently re-introduce 313 × ~136 ms per worktree | **High** |
| **Bound worktree-materialised script execs** — `git checkout` mints new inodes | **Y** | `[MEASURED]` 136.5 ms post-checkout; **420** executable tracked files (313 `.sh`) per worktree; **247** live worktrees | no config — a scoping fact for worktree churn: a worktree that execs all its own scripts costs ~57 s of serialised XprotectService | **High** |
| **Add the terminal to Privacy → Developer Tools** (`kTCCServiceDeveloperTool`) | **UNKNOWN — and the effect is measurably ABSENT today** | `[VENDOR]` nextest docs; `[EXPERT]` Nethercote 9m42s→3m33s (−63 %) on rustc UI tests; `[OSS]` alacritty#8785: works for iTerm (0.011 s) + Terminal.app (0.015 s), **fails for Alacritty (0.378 s)**; `[MEASURED]` kitty here = 121 ms ⇒ not exempt in effect, whatever the grant state | `sudo spctl developer-mode enable-terminal` adds **Terminal.app only**; third-party terminals must be added by hand in System Settings → Privacy & Security → Developer Tools. Read current grants: `sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "select client,auth_value from access where service='kTCCServiceDeveloperTool';"` (unreadable without sudo — tried, `authorization denied`) | **Med** (that it is unexempt now: High. That granting it fixes kitty: Low — alacritty is the same class) |
| **Compile a dispatch binary to replace bash fork chains** | **N — for the assessment reason** | `[MEASURED]` clang-built ad-hoc binary pays the identical 119–170 ms | — (may still be worth it for *fork* cost, §B.4; just not for assessment) | **High** |
| **Notarized + Developer-ID-signed binaries skip the rule scan** | **N (impractical)** | `[EXPERT]` eclecticlight 2026-08-06: "on-demand XProtect check … may be omitted if the first three of those verify correctly" (signature, notarization, CDHash), stated for Tahoe; `[MEASURED]` Apple-signed copy = 0.0 ms here | requires a paid Developer ID + a notarization round-trip per build | **Med** |
| **Third-party Endpoint Security clients multiplying the per-exec tax** | **N — none installed** | `[MEASURED]` `systemextensionsctl list` = 3 extensions, all HID drivers (Razer ×2, Karabiner); non-Apple kexts = 1 | — (rules the axis out) | **High** |

### A.2 Honest cost of the interpreter lever

It is **not** free of security meaning: a script never `execve`'d is a script XProtect never scans.
The counter-arguments, stated so the operator can weigh them rather than be sold them:

- The threat model it removes is "a YARA rule matches a locally generated shell script on its first
  run". These files are produced by the fleet itself, from a checkout that is already trusted.
- It removes *nothing* from binaries: every Mach-O the fleet runs still goes through AMFI (which
  SIGKILLs a broken signature in 1.3 ms — measured) and through the same first-exec path.
- It is per-call-site and instantly reversible (drop the `bash ` prefix). It disables no OS feature,
  writes no TCC row, needs no sudo, and survives OS updates.

Contrast with the Developer-Tools grant, which turns the scan off for *everything the terminal ever
spawns*, persists in a system database, and needs sudo. **The interpreter lever is the narrower,
more reversible instrument and it is 40× on the measured path** — prefer it, and treat the TCC grant
as a second-stage option only if a measurement shows residual tax after the call sites are converted.

### A.3 What is NOT established (named gaps)

1. **Is the cache per-boot?** Inferred from "(device,inode)-keyed and held by a daemon", never
   verified across a reboot. Test: assess a file, note 3 ms, reboot, re-time it.
2. **Does an XProtect definition update flush it?** Untested. The box is at XProtect **5354** /
   config 5304 / payloads 152. If updates flush, the whole fleet re-pays on each Apple push.
3. **Is kitty *granted* Developer Tools and merely ineffective (the alacritty bug), or ungranted?**
   TCC.db is unreadable without sudo. The *effect* is absent either way (121 ms measured).
4. **Does iTerm2 escape it on this box?** alacritty#8785 says iTerm2 does. The fleet uses **both**
   kitty and iTerm2 (handoff-fire drives the it2 API). If iTerm2 is exempt and kitty is not, the
   fleet has a **two-tier exec cost keyed on which terminal spawned the session** — a live,
   unmeasured asymmetry. One-liner to settle it, run once in each terminal:
   `p=/tmp/x$RANDOM.sh; printf '#!/bin/bash\nexit 0\n'>$p; chmod +x $p; time $p`

---

## B · Kernel / OS knobs with SIP ON

| lever | applies-here | evidence (quality) | command/config | confidence |
|---|---|---|---|---|
| **`kern.tty.ptmx_max` raise toward the ~999 architectural cap** | **N for now — margin only** | `[MEASURED]` here: masters **19**, in-use ttys **19**, `ls /dev/ttys*` **35** (= 19 + 16 static legacy) — three methods agree, reproducing §S6.7-MEASURED's "+16 constant" from an independent direction; 18 of 19 held by kitty ⇒ **1 pty per pane**. §S6.7 binds at ~509 panes | `sudo sysctl -w kern.tty.ptmx_max=<n>` — **ramp only ~1.2× per write** (`511→512→514→…→958`; a direct jump returns `Invalid argument`); persist via a `/Library/LaunchDaemons/` plist + `launchctl bootstrap`, **not** `/etc/sysctl.conf` (absent on this box; wiped by OS updates) | **High** |
| **`kern.maxfiles` / `kern.maxfilesperproc` raise** | **N — already ample** | `[MEASURED]` `maxfiles=491520`, `maxfilesperproc=245760`, `ulimit -n=1048576`; `[FORUM-DTS]` Apple DTS: the `launchctl limit` route "was placed behind a SIP barrier … not accidental" | per-shell `ulimit -n` (the DTS-sanctioned path) or a daemon's own launchd plist `SoftResourceLimits` | **High** |
| **`kern.maxproc` / `kern.maxprocperuid`** | **N — already ample** | `[MEASURED]` `maxproc=16000`, `maxprocperuid=10666`, `launchctl limit maxproc = 10666/16000`; measured storms peaked at 736 procs | — | **High** |
| **`launchd` `ThrottleInterval` on the poller fleet** | **UNKNOWN** | `[VENDOR]` `launchd.plist(5)` — default respawn throttle 10 s | per-job plist key; relevant only if a job is crash-looping | **Low** |
| **`vm.compressor_mode`** (the crash term's namesake) | **N — SIP-OFF ONLY, see §F** | `[ANECDOTE]` gist/blog consensus: set via `nvram boot-args="vm_compressor=N"`, requires `csrutil disable` | listed in §F, not recommended | **High** |
| Spotlight / `mdutil` exclusion | **N — settled** | §S6.8: `.worktrees` returns 0 indexed files; `mds` 1.1 % | — | **High** |

`nvram boot-args` is **empty** on this box (`data was not found`) — confirming no boot-arg tuning is
in place and none can be added without disabling SIP.

---

## C · macOS CI / build-farm operator practice

**Verdict: thin, and mostly already-free here.** The published farm tunings target *unattended VM
images*, where the wins are boot determinism and idle-daemon suppression — not many-process
throughput on an interactive workstation.

| lever | applies-here | evidence (quality) | command/config | confidence |
|---|---|---|---|---|
| Disable Spotlight/`mds` | **N — already free** | `[VENDOR]` MacStadium 2021-04-23; `[OSS]` `actions/runner-images` PR #11877 (merged 2025-03-26) disables MDS+Spotlight on macOS 14+ arm64 images | `launchctl unload -w /System/Library/LaunchDaemons/com.apple.metadata.mds.plist` | **High** |
| Disable analytics daemon, notification-center agent, APNS daemon, Time Machine, Handoff/Continuity, graphic effects, solid wallpaper | **Y — small, safe, untried** | `[OSS]` PR #11877 (the most current published macOS-agent tuning list) | per-item `launchctl`/`defaults`; the PR is the canonical list | **Med** (each is fractions of a percent; the aggregate on an interactive desk is unmeasured) |
| Disable Siri/`corespeechd`; `softwareupdate --schedule off`; disable sleep/screensaver | **N — desktop, not a farm** | `[VENDOR]` MacStadium | — | **High** |
| **XProtect/Gatekeeper** in farm tunings | **absent from every published list** | `[VENDOR]`+`[OSS]` — neither MacStadium nor runner-images mentions it | — | **High** |
| **`flock`-style single-build lock across agents** | **Y — directly serves Wave C** | `[ANECDOTE]` developersdigest 2026-06-11: "a simple flock-style lock script that agents call before building—so only one build runs at a time while everything else proceeds in parallel" | a lock wrapper on the compile entry point | **Med** |

**The gap worth naming**: no published macOS CI operator documents XProtect exec cost, even though
the Rust community measured it as the dominant term for spawn-heavy workloads. The farm operators
run *few, long* processes; this fleet runs *many, short* ones. **The CI prior art is the wrong
reference class for this box** — the compiler-toolchain prior art (nextest, Nethercote, Cargo) is the
right one, and it points at exactly one lever: the exec-assessment path.

---

## D · Terminal / render at high pane count

| lever | applies-here | evidence (quality) | command/config | confidence |
|---|---|---|---|---|
| `repaint_delay` / `input_delay` raise | **N — already spent** | `[VENDOR]` kitty performance docs ("if you experience high CPU usage, try increasing `repaint_delay` to 15 or 20"); `[MEASURED]` this box already runs `repaint_delay 16`, `input_delay 5` (vs defaults 10 / 3) | already in `~/.config/kitty/kitty.conf:415,421` | **High** |
| `sync_to_monitor no` | **N — wrong direction** | `[VENDOR]` kitty docs: it *decreases latency* at the cost of tearing; it is not a CPU-reduction knob | — | **High** |
| **Single kitty instance, many OS-windows** (vs many processes) | **Y — already true** | `[ANECDOTE]` kitty docs comparison: one kitty with many windows/tabs = 8 MB GPU + 175 MB host, vs Alacritty 10 MB GPU + 88 MB host **each**; `[MEASURED]` 18 of 19 ptys held by a single `kitty` | keep the single-instance model | **Med** |
| **Occluded / minimised OS-windows costing ~0** | **UNKNOWN — the highest-value unmeasured render lever** | kitty docs are silent on occlusion; no maintainer statement found | Test without touching the fleet: open 2 scratch OS-windows, sample `WindowServer`+`kitty` CPU, minimise one, re-sample. If macOS occlusion is honoured, "≤20 *visible* panes" (§S6.7) can become "≤20 *unoccluded*" — a much cheaper constraint | **Low** |
| **Headless / detached residency** (render cost 0) | **Y — already the program's Phase E** | §S6.7-MEASURED: precondition PASSES (no pty, all six hooks fire, mail reaches the model); blocked on two comms gaps | — | **High** |
| **tmux as the residency substrate** | **N — worse than the current plan** | `[OSS]` tmux#706 / #2408: >200 panes ⇒ "server exited unexpectedly", OOM after heavy use; a tmux pane still allocates a pty, so it buys nothing over kitty on the pty axis and adds a single-point-of-failure server | — | **Med** |
| `abduco` / `dtach` as a thinner detacher | **UNKNOWN** | `[OSS]` abduco: "extremely small C program with minimal dependencies" — session detach without tmux's server model | only relevant if the Phase-E stream-json substrate is abandoned | **Low** |
| kitty remote control for headless orchestration | **Y — already wired** | `[VENDOR]` kitty remote-control docs; `[MEASURED]` `allow_remote_control socket-only` + `listen_on unix:/tmp/kitty-{kitty_pid}` already set | — | **High** |

### D.1 · Live render sample — the 0.025 cores/pane coefficient may be load-dependent

Sampled this session on kitty **0.48.2**, at **3 OS-windows / 3 tabs / 10 panes** (`kitty @ ls`),
with the box at load average **55.64**:

```
WindowServer   30.5 % CPU   245 MB RSS
kitty (proc 1)  7.5 % CPU   355 MB RSS
kitty (proc 2)  7.0 % CPU   149 MB RSS
                -----------
total          45.0 % CPU  =  0.45 cores over 10 panes  =  0.045 cores/pane
```

That is **~1.8× the 0.025 cores/pane** §S6.1 measures. One sample at high contention is not a
refutation — WindowServer serves the whole desktop, not only kitty, so some of the 30.5 % is not
attributable to panes. But if the coefficient is load-dependent rather than constant, the render wall
binds **sooner than 140 panes**, and §S6.7's "render is FIRST, and already over its own alarm floor"
is understated rather than overstated. **Worth re-measuring the coefficient at two load levels before
sizing Phase E**, since every render number in the program is quoted against the 0.025.

Second observation from the same sample: there are **two** `kitty` processes, so the single-instance
assumption behind the "one kitty with many windows is cheaper than N terminals" argument holds only
partially here.

---

## E · Agent-fleet operator practice, and the vendor's own knobs

**The published community numbers are far below this program's design point and are not measurements
of the same thing** — they are per-*active*-agent guidance (token burn, human attention), where this
program's number is per-*resident* session. Cite them for shape, never as a ceiling.

| Source | Claim | Flag |
|---|---|---|
| developersdigest, 2026-06-11 | workflows "up to **16** concurrent agents, **1 000** per run"; agent teams **3–5** teammates; background sessions "as many as your quota survives" | `[ANECDOTE]`, but the 16 is corroborated below |
| Community consensus (superbuilder / mindstudio, 2026) | 16 GB workstation → **6–8** agents; 32 GB VM → **15–20**; "3–5 is the sweet spot" | `[ANECDOTE]` — attention/quota-bound, not host-bound |
| Anthropic, multi-agent research system | orchestrator + **3–5** parallel subagents; multi-agent ≈ **15×** the tokens of chat; token usage explains **80 %** of performance variance | `[VENDOR]` — token economics, says nothing about host resources |
| Claude Code docs, "Run agents in parallel" | no host concurrency numbers at all; only "running several sessions or subagents at once multiplies token usage" | `[VENDOR]` |

### E.1 The knobs that are actually in the installed binary

Extracted from the running 2.1.220 bundle
(`~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe`, a 245 MB Bun single-file
executable — grep it with `grep -a`, there is no `cli.js`):

| lever | applies-here | evidence (quality) | command/config | confidence |
|---|---|---|---|---|
| **Workflow concurrency is `Math.min(16, Math.max(2, cores-2))`** ⇒ **8** on this 10-core box | **Y** | `[MEASURED]` string `Math.min(16,Math.max(2,e-2)` present in the binary; `availableParallelism()` = 10 | not directly settable; it is why a workflow never exceeds 8 here | **High** |
| **`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`** | **Y — an admission-control lever the program has not used** | `[MEASURED]` in-binary model-facing string: *"You can run `${lt}` subagents at once. Do not retry. If the user wants more concurrent subagents, ask them to increase CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS."* | env var, per-session; **bounds fan-out at the source** rather than refusing at the gate | **High** |
| **`CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION`** | **Y** | `[MEASURED]` present in binary env-var table | env var — a per-session budget, complementary to the concurrency cap | **High** |
| **`CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY`** | **Y — the fork-churn lever** | `[MEASURED]` present in binary | env var; caps parallel tool calls ⇒ caps the parallel `Bash` execs that drive both fork churn and the serialised XProtect queue | **Med** (effect unmeasured here) |
| **`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`** | **Y — and it contradicts a standing assumption** | `[MEASURED]` in-binary string: *"…work directly using your tools instead of spawning another agent. If the user explicitly requested deeper nesting, ask them to raise CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH."* | env var | **Med** |
| **`CLAUDE_CODE_PROCESS_WRAPPER`** | **UNKNOWN — potentially the cleanest injection point for §A's interpreter lever** | `[MEASURED]` env-var name present in the binary; no usage context recoverable from the bundle | unknown semantics; worth one probe — if it wraps spawned commands, it is where a fleet-wide `bash `-prefix or resource policy belongs | **Low** |
| **`CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP`** | **N — do not set; it exists as evidence** | `[MEASURED]` present in the binary | its existence implies the harness **already reaps background shells under memory pressure** — a vendor-side control that overlaps `compressor-sentinel`; worth understanding before adding a second reaper | **Med** |
| Per-session node heap `--max-old-space-size=8192` | **N — not binding** | `[MEASURED]` string in binary; §S6.2 measures **232 MB**/session actual | — | **High** |

🚨 **On `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`**: `~/.claude/agents/deep-research.md` states that
nested fan-out "is not operational in stock Claude Code as of May 2026". The installed 2.1.220 binary
carries a *user-raisable depth knob* and a model-facing message telling the agent to ask for it to be
raised. That is **not** proof the `Agent` tool is exposed to a subagent — the historical failure was
tool availability, not a depth check — but it is direct evidence the depth check is now a
**configurable** gate rather than an absent capability. **Re-verify before the next research wave**;
the memory rule *parked-blocker-obsoleted-by-later-fix* names exactly this shape.

---

## F · SIP-off-only levers — LISTED, NOT RECOMMENDED

Recorded so nobody re-derives them and mistakes them for available. Every one of these requires
`csrutil disable` from Recovery, which is out of scope for this box.

| lever | why it is off-limits | source |
|---|---|---|
| `vm.compressor_mode` / `nvram boot-args="vm_compressor=N"` (modes: 1 no-compress/no-swap · 2 compress/no-swap · 3 swap/no-compress · 4 default) | `nvram boot-args` writes require SIP off; mode 2 additionally risks kernel panic near ~50 % compressed — i.e. it **worsens** the exact crash term it appears to target | `[ANECDOTE]` gist/blog consensus |
| `tccutil --service kTCCServiceDeveloperTool --insert <bundleid>` | `tccutil` writes to the protected TCC database; functional only with SIP disabled. The GUI path (System Settings → Developer Tools) achieves the same grant **with SIP on** and is the supported route | `[ANECDOTE]` billmill notes |
| `launchctl limit maxfiles <soft> <hard>` system-wide | fails with "Operation not permitted while System Integrity Protection is engaged"; Apple DTS: the SIP barrier "is not accidental" | `[FORUM-DTS]` Apple Developer Forums #735798 |
| Unloading `XprotectService` / `syspolicyd` | SIP-protected launch daemons; and eclecticlight's 2026-08-06 survey concludes "there doesn't appear to be any direct way of disabling Gatekeeper or on-demand XProtect" | `[EXPERT]` |
| Disabling AMFI (`amfi_get_out_of_my_way=1`) | boot-arg ⇒ SIP off; would also void the 1.3 ms SIGKILL that currently stops tampered binaries for free | `[ANECDOTE]` |

---

## G · Adversarial pass — what a hostile reviewer would say, and what checking it found

1. **"Your 121 ms was measured on a loaded box."** True and stated: load averages were **21.27** at
   measurement and **55.64** twenty minutes later. Because the term is single-threaded and serialised,
   a loaded box makes it *worse*; 121 ms is therefore a lower-variance floor for the operating
   condition, not an inflated number. The quiet-box figure is unmeasured.
2. **"You never checked for a third-party EDR multiplying per-exec cost."** Checked:
   `systemextensionsctl list` returns **3** extensions, all HID drivers (Razer ×2, Karabiner); one
   non-Apple kext. **No Endpoint Security client** — the axis is ruled out, and it also means the
   121 ms is attributable to Apple's own stack alone.
3. **"Your pty numbers are the program's own, re-quoted."** Re-measured by odakin's *independent*
   method (`lsof /dev/ptmx` masters, which they argue is the correct instrument): **19 masters**,
   **19** distinct in-use ttys, **35** `/dev/ttys*` nodes. 35 − 16 = 19. Three methods, one answer —
   §S6.7-MEASURED's "+16 static legacy nodes" correction is confirmed from outside this program.
   18 of the 19 are held by one `kitty` process, confirming **1 pty per pane**.
4. **"The interpreter lever is a security downgrade you're not disclosing."** Disclosed in §A.2, with
   the comparison that matters: it is strictly *narrower* than the TCC grant this dossier's own
   sources recommend, and it is reversible per call site.
5. **"You assumed the assessment cache is per-boot."** Not verified — filed as gap A.3(1) with the
   test, rather than asserted.
6. **"You didn't check whether the fleet's OTHER terminal is exempt."** Correct, and it is the single
   most decision-relevant open measurement (gap A.3(4)): iTerm2 is reported exempt where
   Alacritty-class terminals are not, and this fleet spawns through both.

---

## H · Prior-art sources

**Exec assessment / toolchain**
- Nicholas Nethercote, *Faster Rust builds on Mac*, 2025-09-04 — https://nnethercote.github.io/2025/09/04/faster-rust-builds-on-mac.html — `[EXPERT]` rustc `tests/ui/` **9m42s → 3m33s (−63 %)**; build scripts 0.48–3.88 s → 0.06–0.14 s; identifies the single-threaded `XprotectService`.
- cargo-nextest, *macOS* installation docs — https://nexte.st/docs/installation/macos/ — `[VENDOR]` "even the simplest of tests … taking more than 0.2 seconds" is the tell; prescribes `sudo spctl developer-mode enable-terminal` + manual add for third-party terminals; concedes residual reports after enabling.
- alacritty#8785, 2025-12-14 — https://github.com/alacritty/alacritty/issues/8785 — `[OSS]` the load-bearing negative result: **Alacritty 0.378 s vs iTerm 0.011 s vs Terminal.app 0.015 s** first run, *with* Developer Tools enabled; exemption does not appear to reach child processes.
- Bill Mill, *Avoiding gatekeeper in your terminal* — https://notes.billmill.org/computer_usage/mac_os/Avoiding_gatekeeper_in_your_terminal.html — `[ANECDOTE]` the TCC.db read/write mechanics and the `kTCCServiceDeveloperTool` key.
- Howard Oakley, *Can you disable Gatekeeper and XProtect?*, 2026-08-06 — https://eclecticlight.co/2026/08/06/can-you-disable-gatekeeper-and-xprotect/ — `[EXPERT]` "on-demand XProtect check … may be omitted if the first three of those verify correctly"; concludes there is no supported way to disable either.
- Apple Platform Security, *Gatekeeper and runtime protection* — https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web — `[VENDOR]` "all software in macOS is checked for known malicious content **the first time it's opened**, regardless of how it arrived"; "Gatekeeper also tracks the **provenance** of files written by downloaded software". Silent on Developer Tools, on `syspolicyd`, and on caching.
- Apple Developer Forums #735798 — https://developer.apple.com/forums/thread/735798 — `[FORUM-DTS]` "There is no direct replacement for the previous `launchctl` mechanism. The fact that this was placed behind a SIP barrier indicates that this is not accidental"; sanctioned paths are per-shell `ulimit`, a daemon's launchd plist, or `setrlimit`.
- Mac Internals, *How fork(), exec(), and posix_spawn work on XNU* — https://www.macinternals.app/en/blog/fork-exec-posix-spawn — `[EXPERT]` why `fork()` is structurally expensive on XNU (every BSD proc is married to a Mach task; the VM map and a first thread must be duplicated) — the mechanism behind "~half of CPU in-kernel from fork/exec churn".

**CI / build farms**
- `actions/runner-images` PR #11877, merged 2025-03-26 — https://github.com/actions/runner-images/pull/11877 — `[OSS]` the current published macOS-agent tuning list: solid wallpaper, Handoff/Continuity off, graphic effects off, analytics daemon off, notification-center agent off, Time Machine + daemon off, APNS daemon off, MDS/Spotlight off (macOS 14+). No measured benefit published.
- `actions/runner-images` discussion #5032 — https://github.com/actions/runner-images/discussions/5032 — `[OSS]` Spotlight observed consuming CPU on hosted macOS runners.
- MacStadium, *Simple Optimizations for macOS and iOS Build Agents*, 2021-04-23 — https://macstadium.com/blog/simple-optimizations-for-macos-and-ios-build-agents — `[VENDOR]` Spotlight, Siri/`corespeechd`, `softwareupdate --schedule off`, sleep, screensaver. No XProtect. No measured gains.

**pty / kernel limits**
- odakin/claude-config, `conventions/macos-claude-app-pty-leak.md` — https://github.com/odakin/claude-config/blob/main/conventions/macos-claude-app-pty-leak.md — `[OSS]` the only other public Claude-fleet pty document. Kernel hard ceiling **~960–1023**; `sysctl` raises are limited to **~1.2× per write** (`511→512→514→…→958` succeeds; a direct 1024 returns `Invalid argument`); at exhaustion even `sysctl` deadlocks because it needs a pty; LaunchDaemon-at-boot for persistence; **"Monitor `/dev/ptmx` (master), not `/dev/ttys*` (slave)"** — independent corroboration of §S6.7's +16 correction. (Its *leak* is Claude.app/Electron/node-pty, a different product from Claude Code CLI — do not import the leak claim.)
- Michael Bianco, *How to Increase the macOS Terminal Device Limit* — https://mikebian.co/how-to-increase-the-macos-terminal-device-limit/ — `[ANECDOTE]` sysctl + persistence mechanics.

**Terminal**
- kitty, *Performance* — https://sw.kovidgoyal.net/kitty/performance/ — `[VENDOR]` `repaint_delay` / `input_delay` are "artificial delays introduced into the render loop to reduce CPU usage"; glyph cache in VRAM; rendering in a separate thread. **Silent on how cost scales with window count and on occlusion.**
- kitty, *Control kitty from scripts* — https://sw.kovidgoyal.net/kitty/remote-control/ — `[VENDOR]` `allow_remote_control` / `listen_on`; `--detach`; detach-window-to-new-OS-window.
- tmux#706, tmux#2408 — https://github.com/tmux/tmux/issues/706 · https://github.com/tmux/tmux/issues/2408 — `[OSS]` >200 panes ⇒ server memory failure / "server exited unexpectedly"; the argument against tmux-as-residency at 150.
- abduco — https://github.com/martanne/abduco — `[OSS]` minimal detach/attach without a tmux-style server.

**Agent fleets**
- Claude Code docs, *Run agents in parallel* — https://code.claude.com/docs/en/agents — `[VENDOR]` surfaces and isolation model; **no host concurrency numbers**.
- Anthropic, *When to use multi-agent systems* — https://claude.com/blog/building-multi-agent-systems-when-and-how-to-use-them — `[VENDOR]` orchestrator + 3–5 subagents; ~15× tokens; token usage explains 80 % of performance variance.
- Developers Digest, *Managing a Fleet of Claude Agents*, 2026-06-11 — https://www.developersdigest.tech/blog/managing-a-fleet-of-claude-agents — `[ANECDOTE]` 16 concurrent / 1 000 per run; the **flock-style single-build lock** pattern; `CLAUDE_CODE_ENABLE_TELEMETRY=1` for OTel `cost.usage` / `token.usage` / session counts.
- SuperBuilder / MindStudio parallel-agent guides, 2026 — https://www.superbuilder.sh/blog/run-multiple-claude-code-agents-parallel · https://www.mindstudio.ai/blog/parallel-agentic-development-claude-code-worktrees — `[ANECDOTE]` 6–8 agents on 16 GB, 15–20 on a 32 GB VM, "3–5 is the sweet spot". Attention/quota-bound, not host-bound — do not treat as a ceiling.

---

## I · Ranked, for whoever picks this up

1. **Convert `execve`-of-script call sites to interpreter invocation.** 40× on the measured path,
   no setting changed, reversible per site. Start with hook `command` strings and any code that
   generates-then-executes a script.
2. **Settle the terminal asymmetry** (§A.3(4)) — one `time` command in each of kitty and iTerm2.
   If they differ, the fleet has a two-tier exec cost it does not know about.
3. **Use `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` / `MAX_TOOL_USE_CONCURRENCY` as admission control at
   the source**, alongside the load gate. The gate refuses spawns; these bound fan-out before it forks.
4. **Probe `CLAUDE_CODE_PROCESS_WRAPPER`** — if it wraps spawned commands, it is the single fleet-wide
   injection point for (1).
5. **Measure kitty occlusion** (§D). If occluded OS-windows are free, the render wall at 140 panes
   moves without building the headless substrate.
6. **Re-verify the subagent spawn-depth assumption** in `~/.claude/agents/deep-research.md` against
   the 2.1.220 binary's `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`.
