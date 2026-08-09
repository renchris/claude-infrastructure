# Panel H-CAP-1 — raw return: `cap-userspace`

Fable 5 baseline-blind derivation panelist, 2026-08-09. Session `e2570cc9-65cf-407c-95a8-a55db376d3ee`.
Recovered from the teammate's own transcript after the named-teammate spawn returned no value to the lead (see the write-up for that defect). Verbatim, unedited.

---

<!-- 2026-08-09T21:06:49.333Z -->

## RANKED SATURATION TERMS (by gauge-blindness)

### 1. PTY namespace — the one limit nobody tuned **[DERIVED + CONFIRMED]**
- **Ceiling:** `kern.tty.ptmx_max = 511` (measured). Architectural hard cap ≈ **999** even if raised — pty slave devices are named `/dev/ttys%03d`, and XNU's sysctl handler rejects values above three digits (derivation from XNU `tty_ptmx.c`; verifiable by a refused `sysctl kern.tty.ptmx_max=1500`, not run).
- **Decisive context:** every OTHER ceiling on this box has already been raised — `kern.maxproc` 16000 (stock 4000), `kern.maxprocperuid` 10666 (stock 2666), `kern.maxfiles` 491520 (stock 245760), shell `ulimit -n` 1048576. **ptmx_max sits at stock 511.** The tuning fingerprint proves prior saturation episodes on this box hit proc/fd walls; the pty wall is the one that hasn't been hit yet and hasn't been raised.
- **Scaling law:** linear in *panes*, not sessions — currently 24 ptys for 6 sessions (kitty subtree = 30 procs), i.e. ~4 ptys/session-equivalent counting split-right handoff panes, teammate panes, notify-back panes. 150 sessions at the fleet's own pane doctrine ⇒ 300–600+ ptys; with teams it crosses 511, and no tuning gets it past ~999. **Threshold cliff.**
- **Gauge blindness (maximal):** at the cliff, `posix_openpt` returns EAGAIN — kitty "could not open pty", `handoff-fire --split-right` fails, teammate spawns fail — with CPU idle, memory free, fd counts healthy, and no counter anywhere trending toward it. Nothing in any readout watches `/dev/ttys*` count.
- **Confidence: HIGH** (limit measured; consumption rate measured; hard cap is derivation).

### 2. Single-writer coordination locks — O(N²) aggregate wait **[DERIVED + CONFIRMED as structure; magnitude UNCONFIRMED]**
- **Structure confirmed in code:** `scripts/land-lock.sh` + `ship-land.sh` (one global landing serializer); `/tmp/claude-accounts-cache.json` with "flock single-flight, TTL 90s" (`bin/claude-accounts:89`) called from Stop-path hooks (`hooks/completion-assert.sh`, `hooks/relay-verbatim.sh`); shared checkout locks below. Plus `/tmp` shows three generations of heal locks (`claude-accounts-heal-next{,2,4}.lock`) — lock proliferation is already the repo's coping pattern.
- **Ceiling:** not a kernel number — throughput ceiling = 1/(critical-section time). A serializer with a T-second hold admits 3600/T lands per hour *fleet-wide*; N sessions each needing it wait Θ(N·T) each, Θ(N²·T) aggregate. At 150 sessions even T=30s means the land pipe alone caps at ~120/hr while sessions queue.
- **Gauge blindness:** a session blocked on flock is *sleeping* — macOS load average counts only runnable threads, so 100 queued sessions show as an idle box. To every observer (and to the sessions' own "thinking" indicators) the fleet looks calm while throughput has collapsed.
- **Confidence: HIGH on mechanism, MEDIUM on which lock binds first** (land-lock is the best candidate: longest hold time).

### 3. One `.git` behind 402 worktrees — shared-ref/lock storms **[DERIVED + CONFIRMED]**
- **Confirmed shape:** `~/Development/claude-infrastructure/.git` carries **402 worktree registrations** (measured), 280 MB, 16 packfiles; six sibling `wt-*` checkouts each report the same 403. Every ref write from any worktree takes the *shared* `packed-refs.lock`; `config.lock` races on parallel worktree creation are already an observed incident class (ambient context, GH #34645 — noted as contamination). Any `git gc --auto` triggered from one worktree locks the object store for all 150.
- **Scaling law:** lock-collision probability ~ (writers × hold-time) — quadratic in concurrent committers. Also every `git worktree list` / prune walk is O(402) regardless of N.
- **Gauge blindness:** failures present as *intermittent git flakes* ("cannot lock ref 'HEAD'") attributed to individual sessions, never to the shared store; no gauge aggregates lock-retry counts.
- **Confidence: HIGH.**

### 4. Vnode table / name-cache working-set overflow **[DERIVED + PARTIALLY CONFIRMED]**
- **Ceiling:** `kern.maxvnodes = 263168` (measured; table already fully populated: `num_vnodes == desired == 263168`, lifetime recycles 160.6M ≈ total newvnode calls — steady-state allocation is 100% recycle). In-use now ~60k (free 203k), so today it breathes.
- **The derivation:** 403 worktrees × O(10³–10⁴) files each = millions of distinct inodes; a fleet-wide wave of `git status`/hook scans cycles the entire 263k-entry cache multiple times per sweep → name-cache hit rate collapses → every `stat()` becomes a disk walk. Scales with (concurrent sessions × active tree breadth) — soft threshold at working-set ≈ maxvnodes.
- **Gauge blindness:** everything gets uniformly slow; load average stays LOW because I/O-blocked threads aren't runnable on macOS; memory pressure normal (vnodes are wired kernel memory no user gauge shows).
- **Confidence: MEDIUM** — the confirming probe is P4 below (recycle-delta during one sweep).

### 5. Spotlight + fseventsd write amplification **[DERIVED + CONFIRMED enabled]**
- **Confirmed:** `mdutil -s` → **Indexing enabled** on `/System/Volumes/Data` — all 403 worktrees, all node_modules churn, all transcript JSONL appends are being indexed. Each session write fans out to fseventsd streams (every Node `fs.watch` = one FSEvents client through ONE daemon) + mdworker crawls.
- **Scaling:** linear in fleet write rate, but the *cost lands on a shared single daemon pair*, so per-session latency degrades super-linearly under bursts.
- **Gauge blindness:** mds/fseventsd CPU is attributed to "the system", never to session count; the symptom is fs-op latency, invisible in load.
- **Confidence: HIGH that it's active; MEDIUM that it binds before #4.**

### 6. kitty's fd budget under launchd's soft-256 **[DERIVED + UNCONFIRMED — decisive probe named]**
- kitty (pid 600) is a **single process holding every pane's pty master**: 99 fds at 24 windows ⇒ slope ≈ 2.3 fds/window over a ~45-fd baseline ⇒ ~**390 fds at 150 windows**. `launchctl limit maxfiles` soft = **256** for GUI-launched processes. If kitty does not setrlimit itself, new-window creation fails at ~90–95 windows — *before* the pty cliff.
- **Deciding probe (self-deciding, zero risk):** watch `lsof -p 600 | wc -l` as windows grow; if it ever exceeds 256 with kitty alive, the limit was self-raised and this term is REFUTED. Alternatively grep kitty source for `setrlimit`/`RLIMIT_NOFILE`.
- **Gauge blindness:** total — "could not create window" from the emulator, box idle.

### 7. `kern.ipc.somaxconn = 128` (stock) — burst fan-in to any listening socket **[DERIVED + UNCONFIRMED]**
- Any coordination daemon with a unix/tcp listener: a *synchronized* event (broadcast, reset-poller tick, quota window rollover) making 150 sessions connect inside one accept-loop iteration overflows the 128 backlog → ECONNREFUSED, which fleet scripts characteristically misread as "daemon dead" and then act on. Threshold, burst-driven, invisible between bursts.
- Probe to decide: identify listeners (`lsof -U -a -u chrisren` filtered to LISTEN) and whether any has ≥1 caller-per-session fan-in on a shared trigger.

## REFUTED (by measurement, this session)
- **System-wide open files:** `kern.num_files` 6835 vs ceiling 491520 — two orders of headroom; ~28 fds per claude process. Not a binder at 150×.
- **Per-user process count:** 451 now; per-session trees measured at 1–6 procs ⇒ ~1500–2500 projected vs maxprocperuid 10666 (already tuned up). Not a binder — *but the tuning itself is evidence it once was*.
- **Total threads:** 3554 now; claude = 29 threads/session ⇒ ~8–30k projected (with teams) vs `kern.num_threads` 81920. Headroom holds unless teams multiply beyond 6×.
- **Disk free-space collapse:** 4.9 Ti available on a 7.3 Ti volume. Dead.
- **WindowServer client/surface budget:** kitty is ONE WindowServer client rendering panes internally — the 150-session GUI cost never reaches WindowServer. Dead (and a real, non-obvious advantage of kitty over per-window emulators).
- **Ephemeral ports / API sockets:** ~16k port range vs a few conns/session. Dead.

## NEGATIVE SPACE (adjacent, unwatched)
- **syspolicyd/amfid exec-check serialization:** 150 sessions × Bash-tool exec churn funnels through one security daemon; exec *latency* (not CPU) is the symptom, and nobody measures time-to-first-instruction of a spawned shell.
- **Wired kernel memory** (threads × 16–64 KB kernel stacks, mach ports, vnodes): "free memory" gauges show user pages; wired growth at 30k threads is invisible until pageout behavior changes.
- **`/tmp` as a coordination substrate:** the fleet's locks, caches, fire-briefs, and telemetry all live in a wipe-on-panic directory (12 telemetry files now); at 150 sessions a single reboot atomizes the coordination layer mid-flight — a correlated-failure axis, not a saturation one.

## FALSIFIABLE RUNTIME PREDICTIONS
1. **[pty slope]** `ls /dev | grep -c '^ttys'` = 24 now. Fire k split-right handoff panes ⇒ count rises by exactly k. If the per-session pane ratio (≥2) holds, the fleet crosses **511 between ~120 and ~170 concurrent session-equivalents**. Refutes #1 if the ratio measured across the next scale-up is <1.5.
2. **[pty cliff]** Staged, controlled: a python loop of `pty.openpty()` (in one process, immediately closed on exit) fails at exactly `511 − <current count>` opens. Expected errno: EAGAIN/ENXIO. (Run only in a quiet window — it briefly consumes the namespace.)
3. **[kitty fd]** `lsof -p $(pgrep -x kitty) | wc -l` tracked against window count: predict slope 2–3 fds/window. **If the count passes 256 with kitty alive → term #6 REFUTED; if window creation fails as it approaches 256 → CONFIRMED.**
4. **[vnode working set]** `sysctl vfs.vnstats.num_recycledvnodes` before/after one serial `git status` sweep of all 403 worktrees: predict delta **> 263,168** (i.e., the sweep alone cycles the whole cache ≥1×). Delta ≪ table size refutes #4.
5. **[lock queue]** From ship/land logs (timestamps around `land-lock.sh` acquire/release): predict p95 land-latency at k concurrent shippers ≈ k × solo-land time, i.e., super-linear wall-time growth with zero CPU growth. A flat p95 at k≥5 refutes #2's binding-lock choice (then re-aim at the accounts flock).

## CAMPAIGN / GENERATOR CANDIDATES
1. **The visible-pane doctrine has a hard numeric ceiling (≤999 ptys, ever, on this box).** A headless/pty-less session substrate (sessions run detached; panes are *views* attached on demand) dissolves: the pty cliff (#1), the kitty fd slope (#6), orphaned-pane reaping, and the pane-anchor fragility class in the handoff machinery — all become no-ops because a session no longer *is* a pane. This is the only finding that cannot be tuned away: at 150 sessions × teams, the doctrine itself is the ceiling.
2. **One object store behind 402 worktrees.** Sharding (per-cluster clones with a shared alternates store, or reftable + maintenance serialization owned by ONE daemon) dissolves ref-lock flakes (#3), config.lock spawn races, gc-vs-fleet contention, and shrinks the vnode working set (#4) in the same stroke.

---
**Contamination noted:** ambient CLAUDE.md/MEMORY.md (loaded, not requested) contain prior findings I could not unsee — config.lock races GH #34645, a measured 414–833s lock tail, /tmp telemetry wipe. I cite them only as corroboration; the pty, vnode, somaxconn, Spotlight, and kitty-fd derivations are independent of them. **Probes spent:** 6 read-only Bash batches (sysctl/launchctl/ulimit; proc+thread+pty census; lsof on 3 pids; worktree + object-store census; lock-chokepoint grep; per-session tree sizes). Nothing heavy, nothing forked wide, nothing written.
