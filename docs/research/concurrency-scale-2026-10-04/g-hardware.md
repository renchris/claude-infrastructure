# G: hardware paths to ~1000 concurrent Claude Code agents (local, no API-billed cloud)

Date: 2026-10-04. Read-only research. Tags: **MEASURED** = taken on this box today or in the fleet's
own docs; **INFERRED** = derived by me from cited inputs; prices carry a URL each.

## 0. Answer first

1. **No single Mac reaches 1000 agents at today's workload mix.** The biggest Mac (M5 Ultra 36-core)
   tops out at about **230 agents on CPU** (INFERRED). Two macOS-only walls also stay the same however
   many cores you buy. XProtect's first-exec scan runs on one thread
   (MEASURED: 8-way parallel = 118.9 ms/file vs 127.3 serial). The pty limit is about 999
   (fleet doc). The cheapest per slot is a fleet of **5–9 Apple boxes** (M5 Pro mini 18C/64GB, or
   M5 Ultra 30C/96GB) at **$23–33K** in total.
2. **Linux is better per dollar for this workload, and the gap comes from the OS, not the chip.**
   Process creation costs about 10× less CPU on Linux (macOS 2.0–3.0 ms CPU per spawn MEASURED here at load
   ~160, against a published 0.13–0.24 ms on Linux). Linux has no XProtect and no WindowServer, and it gives
   per-session cgroups. My planning multiplier is **1.3–1.8× more agents per unit of
   CPU throughput** (INFERRED; the range is wide because it has not been measured on our own mix).
3. **Sessions run fine on a remote Linux box with the same Max accounts.** Generate a 1-year
   `claude setup-token` token per account and pass it as `CLAUDE_CODE_OAUTH_TOKEN`, with one `CLAUDE_CONFIG_DIR` per
   account (vendor docs). This also removes the fleet's OAuth refresh-herd wall. The
   cost is porting: **259 of 713 fleet scripts and 44 of 99 hooks** call macOS-only commands
   (MEASURED grep).
4. **Agents per core at today's mix:** ~**10 agents per M1-Max core when the CPU is pinned** (MEASURED) and ~**5 per
   core when comfortable** (INFERRED, range 3.5–7). Capacity scales with **total multi-core throughput
   × how cheap the OS makes process creation**. RAM is the second limit (about 0.4 GB per agent all-in).
   Single-thread speed mostly changes latency, not capacity. The one exception is the serial XProtect queue on
   macOS, where single-thread speed is the only thing that helps.
5. **Next step: one ~$4K Linux box (Ryzen 9 9950X, 128 GB).** Use it first as the offload target for
   Chrome and headless browsers, then as a pilot running real sessions in tmux, to measure the Linux
   multiplier. **End state:** a headless Linux fleet (2× Threadripper 9980X, or 4–5× 9950X) with the Mac
   kept as the cockpit. **Before any of that:** the 4 Max accounts sustain only **6.2–11.0 concurrently
   active sessions** (fleet doc). 1000 *active* agents (~150 sessions) is 14–24× more than that quota
   allows. Hardware pays off only if most of the 1000 sit idle, or the account count grows.

## 1. Fleet baseline (what the model is fitted to)

| Quantity | Value | Tag / source |
|---|---|---|
| Host | MacBook Pro M1 Max, 10 cores (8P/2E), 64 GB | MEASURED `sysctl` |
| Load now | 122–171 on 10 cores; CPU 61% user / 39% sys / **0% idle** | MEASURED `top -l 2`, `uptime` 01:42–01:52 |
| Memory now | 57 GB used (10 GB wired, 7.3 GB compressor), 5.6 GB free | MEASURED `top` (differs from the brief's "68% free", so memory is not reliably slack) |
| claude processes | 28–30 procs, **12.8 GB RSS (~0.45 GB each)**, **0.37 cores in total (~4% of the box)** | MEASURED `ps`, `top` 2nd sample |
| Chrome ("Google" + "Browser") | 195 procs, **25 GB RSS**, 1.5 cores in top's 2nd sample (2.3 + 1.5 by ps decayed %) | MEASURED |
| XprotectService + syspolicyd | **0.52 cores** | MEASURED `top` 2nd sample |
| WindowServer | 0.3–0.8 cores | MEASURED (`top` / `ps`) |
| Process creation rate | **~500 new pids/s** | MEASURED (pid delta over 10 s) |
| CPU visible to per-process sampling | **only 407% of 1000%**. The other ~59% is short-lived churn plus kernel time | MEASURED (`top -l 2 -n 300` sum) |
| Spawn cost on this box | posix_spawn `/usr/bin/true`: **2.0 ms CPU (1.1 ms sys)**, 9.4 ms wall; fork+exec: **3.0 ms CPU (2.0 ms sys)**, 12.9 ms wall | MEASURED (Python loop ×300 at load ~160; Apple-signed binary, so no XProtect scan) |
| XProtect novel-inode exec | 121–213 ms first exec; serialises across threads | MEASURED, `docs/research/scaling-bottlenecks-2026-08-09/11-prior-art.md:35,46` |
| Load per genuinely-active session | 2.5–5 runnable threads | `docs/research/scaling-bottlenecks-2026-08-09.md:34` |
| Memory per session (2026-08) | 340 MB arrival cost + **~507 MB of MCP children** | same doc `:31-32` |
| Sustainable active sessions on 4 Max accounts | **6.2–11.0** | same doc `:36`, `:370` |
| pty cap (macOS) | ~509 panes at the current sysctl; ~999 architectural cap | `11-prior-art.md:105` |

So 500 spawns/s × 2–3 ms ≈ **1.0–1.5 cores spent only on creating processes** on macOS, before any
spawned program does work (INFERRED from the two MEASURED numbers). The brief's premise holds: claude
itself is ~4% of the CPU. The CPU goes to tool work and process churn.

## 2. Agents-per-core model (key question d)

- **Unit:** one M1M = the multi-core throughput of an M1 Max (Cinebench 2024 MC **796**,
  [cpu-monkey](https://www.cpu-monkey.com/en/benchmark-apple_m1_max_32_gpu-cinebench_2024_multi_core)).
  Some sources put the M1 Max nearer ~1,000. If so, every ratio below shrinks by ~20%.
- **Pinned point:** ~100 agents per M1M (MEASURED: the brief's ~100 agents at 0% idle).
- **Comfortable point, used for planning:** **~50 agents per M1M on macOS** (INFERRED, band 35–70). The
  felt lag starts at ~15 sessions, and the fleet doc's comfortable active band is ~4–8 sessions.
- **Linux:** ×1.3–1.8, so **65–90 agents per M1M** (INFERRED). Derivation, against today's 10 cores:
  - Spawn overhead drops from 1.0–1.5 cores to ~0.1–0.15.
  - XProtect and syspolicyd (0.5 cores) go away.
  - WindowServer and terminal rendering (0.3–0.8) go away on a headless box.
  - Part of the 39% sys time goes away (the macOS VM compressor and Mach overhead).
  - Total: ~2–3 of 10 cores back, ≈ 1.3×. The upper end needs the dyld/startup and sys
    differences to also favour Linux, which the 10× spawn benchmark suggests but no one has measured on our mix.
- **RAM per agent: ~0.4 GB all-in + 4–12 GB per host baseline** (INFERRED: (57 GB used − ~12 GB
  baseline) / ~100 agents ≈ 0.45 GB. The brief's "68% free" snapshot implies ~0.2 GB). Chrome is ~25 GB of today's
  total, so moving browsers off the host roughly halves RAM per agent.
- **What scales capacity, in order:**
  1. Multi-core throughput × OS spawn efficiency. The work is hundreds of short processes per
     second, which spread across cores almost perfectly.
  2. RAM. It binds first on 32–64 GB boxes and on any box with Chrome resident.
  3. Single-thread speed. It sets tool latency (tsc, bats wall time) and the macOS serial XProtect queue: 0.4
     cores of single-threaded demand at ~100 agents projects to **~1 full core at ~250 agents on M1-class
     cores, or ~450 on M5 super cores**. That is a hard per-host ceiling on macOS unless novel-inode execs are cut
     (INFERRED from the MEASURED 0.4 cores and the serialisation result).

## 3. Options table

Capacity = min(CPU cap, RAM cap). CPU cap = (Cinebench 2024 MC ÷ 796) × 50 on macOS, or × 65–90 on Linux.
RAM cap = (RAM − baseline) ÷ 0.4 GB. All capacities are INFERRED; all prices are cited.
Core legend for Apple: S = "super" (top-tier P), P = performance, E = efficiency.

| Config | Cores | RAM | Price (USD) | Est. agents (comfortable) | $ / agent slot | Caveats |
|---|---|---|---|---|---|---|
| **Today: MBP M1 Max** | 10 (8P/2E) | 64 GB | sunk | **~50** (pinned at ~100, MEASURED) | — | CPU-bound; 39% sys |
| Mac mini M6 | 12 (2S/4P/6E) | 32 GB (max) | **$1,299** (24 GB $1,299 + 32 GB +$200; [EveryMac](https://everymac.com/systems/apple/mac_mini/specs/mac-mini-m6-12-core-cpu-12-core-gpu-2026-specs.html)) | **~60** (RAM-bound; CPU ~85 from GB6 MC 20,891 vs 12,247) | **~$22** | 32 GB ceiling; 17 units for 1000 = ~$22K plus switch and orchestration |
| **Mac mini M5 Pro 18C** | 18 (6S/12P) | 64 GB | **$2,899** ($1,899 base + $1,000 for 64 GB; [Apple store](https://www.apple.com/shop/buy-mac/mac-mini), [EveryMac](https://everymac.com/systems/apple/mac_mini/specs/mac-mini-m5-pro-18-core-cpu-20-core-gpu-2026-specs.html)) | **~120** (CPU 115–135 at GB6 MC 28,699 ≈ M5 Max; RAM 135) | **~$24** | Best Apple $/slot; 8–9 units = $23–26K; 2.5GbE base |
| Mac Studio M5 Max | 18 (6S/12P) | 64 GB | **$3,499** ($3,099 for 18C/40G/48 GB + $400; [EveryMac](https://everymac.com/systems/apple/mac-studio/specs/mac-studio-m5-max-18-core-cpu-40-core-gpu-2026-specs.html)) | **~130** (CB24 2,073–2,255 ([LaptopMedia](https://laptopmedia.com/processor/apple-m5-max-18-core-cpu-40c-gpu/)) → 2.6–2.8 M1M) | ~$27 | Same CPU as the M5 Pro mini for +$600 |
| Mac Studio M5 Max 128 GB | 18 (6S/12P) | 128 GB | **$5,099** (+$2,000 for 128 GB; same EveryMac page) | ~135 (CPU-bound; RAM fits ~290) | ~$38 | RAM wasted at this mix |
| **Mac Studio M5 Ultra 30C** | 30 (10S/20P) | 96 GB | **$5,499** ([Apple store](https://www.apple.com/shop/buy-mac/mac-studio); [Macworld](https://www.macworld.com/article/3220024/apple-announces-the-m5-ultra-mac-studio-with-up-to-512gb-of-ram.html)) | **~195** (CPU ~3.9 M1M scaled from the 36C; RAM 210) | **~$28** | Best single-Mac step; 5–6 units for 1000 = $28–33K |
| Mac Studio M5 Ultra 36C | 36 (12S/24P) | 256 GB | **$10,799** (96→256 GB adds $4,000; [aicybr](https://aicybr.com/blog/mac-studio-m5-max-m5-ultra-2026-price-specs-mac-mini-m6-comparison), [EveryMac](https://everymac.com/systems/apple/mac-studio/specs/mac-studio-m5-ultra-36-core-cpu-80-core-gpu-2026-specs.html)) | ~230 (CB24 MC 3,701 → 4.65 M1M; RAM fits ~610) | ~$47 | CPU-bound and RAM wasted. 512 GB ships late Oct, price TBA. The serial XProtect queue (~450) and the ~999 pty cap still apply |
| **Linux: Ryzen 9 9950X** | 16C/32T (Zen 5) | 128 GB DDR5 UDIMM | **~$3.5–4.5K** (CPU $434–649 ([whatpsu](https://de.whatpsu.com/articles/1813-The-price-of-the-AMD-Ryzen-9950X-has-been-reduced-by-33-from-the-manufacturers-suggested-retail-price-now-available-for-434)); RAM $17–22/GB ([openclawdc](https://openclawdc.com/blog/ram-prices-local-ai-september-2026/)) ≈ $2.2–2.8K; board, PSU and SSD ~$0.8–1.1K INFERRED) | **~190–265** (CB24 2,340 ([cpu-monkey](https://www.cpu-monkey.com/en/benchmark-amd_ryzen_9_9950x-cinebench_2024_multi_core)) → 2.94 M1M × 65–90; RAM fits ~310) | **~$13–24** | Best $/slot overall; 4 DIMM slots (max ~256 GB); no ECC by default; 4–5 boxes for 1000 = $15–22K |
| Linux: Threadripper 9980X | 64C/128T (Zen 5) | 256 GB RDIMM | **~$14–19K** (CPU $4,819, low $3,999 ([TechSpot](https://www.techspot.com/products/cpu/amd-ryzen-threadripper-9980x-32ghz-socket-str5.309476/)); RDIMM $26–45/GB ([Newegg kit $1,691.99/64 GB](https://www.newegg.com/p/pl?d=ddr5+ecc)) ≈ $6.7–11.5K; board and rest ~$2.2K INFERRED). Prebuilt System76 Thelio Major 9980X/128 GB = $14,264 (search summary citing [Phoronix](https://www.phoronix.com/review/intel-xeon-600-amd-threadripper-9000/15)) | **~540–630** (CB24 6,632 ([TechSpot review](https://www.techspot.com/review/3020-amd-ryzen-threadripper-9980x-9970x/)) → 8.3 M1M × 65–90 = 540–750; RAM fits ~630) | ~$22–34 | One box ≈ 60% of the goal; 2 boxes for 1000. RDIMM prices are volatile (64 GB single modules list at $2.4–3.1K) |
| Linux: TR 9980X 512 GB | 64C/128T | 512 GB | ~$20–30K (RAM $13–23K at $26–45/GB; 128 GB RDIMMs scarce ([Fusion](https://info.fusionww.com/blog/inside-ddr5-rdimm-supply-why-96gb-and-128gb-modules-are-hard-to-find))) | ~540–750 (CPU-bound) | ~$27–56 | Extra RAM unused unless agents are idle-resident |
| Linux: EPYC 9965 1S | 192C (Zen 5c) | 768 GB RDIMM | ~$29–48K (CPU ~$6–10K street vs $14,813 list ([TechRadar](https://techradar.com/pro/one-of-amds-most-powerful-cpus-gets-a-60-percent-price-cut-192-core-epyc-9965-cpu-costs-less-than-usd6000-new-and-i-cant-explain-why-its-so-cheap)); RAM $20–35K) | ~850–1,400 (throughput assumed 1.6–1.9× the 9980X; INFERRED, no CB24 number) | ~$20–56 | The only plausible single host for 1000; server chassis and noise; RAM is most of the cost |
| **Offload only:** keep the M1 Max + a 9950X/128 GB tool box | Mac 10 + Linux 16C | 64 + 128 GB | **~$3.5–4.5K** added | **Mac ~125–200** (INFERRED: Chrome, tests, OCR and ffmpeg are ~75–85% of Mac CPU, but hooks, git and render stay local; RAM per agent falls to ~0.2–0.25 GB) | ~$27–53 per *added* slot | Every tool call has to be wrapped (ssh/CDP/queue); worktrees must be synced; ceiling stays ~200 because hooks run locally |

Apple chip and memory facts: [Mac Studio specs](https://www.apple.com/mac-studio/specs/) (M5 Max 18C = 6S+12P,
M5 Ultra 30C = 10S+20P or 36C = 12S+24P, max 512 GB) and [Mac mini specs](https://www.apple.com/mac-mini/specs/)
(M6 = 2S+4P+6E with 32 GB max; M5 Pro = 5S+10P or 18C). Prices went up in June 2026. The M3 Ultra launched at
$3,999 and was $5,299 after the hike ([aicybr](https://aicybr.com/blog/mac-studio-m5-max-m5-ultra-2026-price-specs-mac-mini-m6-comparison)).
RAM cost is now roughly equal across platforms: Apple's upgrades work out to ~$25/GB, DDR5 UDIMM is $17–22/GB, and RDIMM is $26–50/GB.

## 4. Is Linux better per dollar for fork/exec-heavy shell work? (key question b)

**Yes, by about an order of magnitude on process creation.** The evidence points the same way, but none of
it is a same-hardware A/B test.

| Evidence | macOS | Linux | Tag |
|---|---|---|---|
| Go os/exec spawn, sequential ([fastexec](https://pkg.go.dev/github.com/zchee/fastexec)) | **2.47 ms** (M3 Max) | **0.243 ms** (ARM64, 8 vCPU) | published; ~10× |
| Same, parallel across all cores | 485 µs/op on 16 cores ≈ 130 spawns/s/core | 45 µs/op on 8 vCPU ≈ 2,800 spawns/s/core | published; ~20× per core |
| fork+exec of a dynamically linked binary ([HN](https://news.ycombinator.com/item?id=34287881)) | — | 131 µs (i5-6600K); 31 µs static | published |
| Process vs thread creation ratio ([bitsnbites](https://www.bitsnbites.eu/benchmarking-os-primitives/)) | 7–8× | 2–3× | published, 2017, updated 2024 |
| This box under fleet load | 2.0–3.0 ms CPU per spawn, 1.1–2.0 ms of it sys | — | MEASURED |
| First exec of a novel script inode (XProtect) | 121–213 ms, serial | none | MEASURED (fleet doc); [Nethercote](https://nnethercote.github.io/2025/09/04/faster-rust-builds-on-mac.html): rustc UI tests −63% once exempted |
| PATH lookup in libuv/Node spawn ([Tencent #868](https://github.com/Tencent/teamai-cli/issues/868)) | 30–67 ms for a bare-name `git` (vs 2.9–3.8 ms with an absolute path) | a cheap failed execvp | published 2026-09-28 |
| fork() with MAP_JIT regions ([libuv #3050](https://github.com/libuv/libuv/issues/3050)) | ~100× slower since Big Sur | n/a | published |

Other Linux advantages that bear on scale (vendor docs or the fleet's own walls):
- **pty limit:** 4096 by default and raisable ([kernel devpts](https://www.kernel.org/doc/html/latest/filesystems/devpts.html)), against
  macOS ~511 raised to ≤ ~999 by hand.
- **pid space:** 4M on Linux against macOS's 99,999. The fleet already wraps pids every ~108 s at 923 pids/s.
- **Memory isolation:** cgroup `MemoryMax`/`cpu.weight` per session. That would contain the measured 41 GB claude.exe
  self-burst that the compressor-panic crash class rides on (`scaling-bottlenecks-2026-08-09.md:32`).
  macOS has no per-process memory cap.
- **The Apple-hardware route is closed:** Linux cannot run natively on M5 Studios or minis. Asahi reached M3 (minus
  the Ultra) on 2026-09-06, and "M4 and M5 Macs are not ready for daily Linux use"
  ([linuxiac](https://linuxiac.com/asahi-linux-nears-official-support-for-apple-m3-macs/),
  [Phoronix](https://phoronix.com/news/Apple-M3-Asahi-Linux-2026)).
- **A Linux VM on an M5 Mac** (Virtualization.framework, OrbStack or Lima) is the one way to get Linux spawn
  costs on Apple silicon. I did not measure it: Docker Desktop is installed but its daemon is down, and I
  chose not to start a VM on a box at load 160 with 5.6 GB free. That leaves it unquantified (INFERRED that it helps).

## 5. Remote Linux with the same Max auth: what works and what breaks (key question c)

**Works (vendor docs: [code.claude.com/docs/en/iam](https://code.claude.com/docs/en/iam)):**
- **Linux storage:** credentials live in `~/.claude/.credentials.json` (0600), one per `CLAUDE_CONFIG_DIR`, so the
  4-account layout carries over unchanged.
- **Login over SSH:** the browser shows a code and you paste it into the terminal ("common in WSL2, SSH sessions, and
  containers").
- **`claude setup-token`:** produces a **one-year** subscription token for `CLAUDE_CODE_OAUTH_TOKEN` (Pro, Max, Team or
  Enterprise). That removes the fleet's rotating-refresh-token herd (`scaling-bottlenecks-2026-08-09.md:35`:
  one expiry instant per ~37 sessions, where one losing racer logs out the whole account).
  - Limits: it "can only make model requests", so no Remote Control and no claude.ai connectors. `--bare` ignores it.
- **Quota is per account, not per device**, so moving sessions to Linux changes nothing about quota (INFERRED from the docs'
  per-account credential model).
- **Terminal access:** tmux on the server, with kitty on the Mac ssh-ing in. mosh survives roaming but has weak scrollback
  and OSC-52 support (INFERRED).

**Breaks (MEASURED grep over `hooks/ bin/ scripts/` in `claude-infrastructure`):**

| Dependency | Files | Linux replacement |
|---|---|---|
| `it2*` / iTerm references | 123 | drop (kitty or tmux only) |
| `/opt/homebrew` paths | 88 | PATH abstraction |
| BSD `stat -f` | 82 | GNU `stat -c` (mechanical) |
| `osascript` | 57 | notify over ssh to the Mac, or drop |
| `launchctl` / LaunchAgents (39 claude plists loaded) | 54 / 17 | systemd user units and timers |
| `kitty @` / `kitten @` pane control | 50 | `tmux` commands; the local kitty only attaches |
| Keychain (`security …-generic-password`) | 33 | the credentials file or `pass` |
| `vm_stat` / `memory_pressure` / `sysctl hw.*` | 35 | `/proc/meminfo`, PSI |
| `date -j` | 24 | GNU `date -d` |
| `caffeinate` / `pmset` | 20 | n/a |

- **Totals:** **259 of 713 scripts** and **44 of 99 hooks** contain at least one macOS-only call.
- **Hooks come first:** hooks run *where the session runs*, on every tool call, so they must be ported before any session moves.
- **Not affected:** Claude Code itself runs on Linux.

## 6. Offloading only the heavy tool work

- **Target:** Chrome is the largest single consumer: 195 processes, 25 GB, about a third of the CPU visible to top
  (MEASURED). Pointing chrome-devtools-mcp or agent-browser at a remote CDP endpoint moves that wholesale.
  bats, tsc, OCR and ffmpeg need a remote-exec wrapper plus synced worktrees.
- **Ceiling:** ~125–200 agents on the M1 Max (INFERRED). The hook fork chain, git, kitty rendering
  and the serial XProtect queue all stay on the Mac. This is a good *next* step, but it is not a route to 1000.

## 7. Recommendation

**Next hardware step (about $4K):** buy **one AM5 Linux box: Ryzen 9 9950X, 128 GB DDR5, 2 TB NVMe**.
1. **Week 1:** use it as the offload target for browsers and heavy tools. That buys the M1 Max roughly 2–3× headroom.
2. **Week 2:** run 10–20 real sessions in tmux on it under `CLAUDE_CODE_OAUTH_TOKEN`, with hooks ported first. Measure
   agents per M1M on Linux against the 1.3–1.8× multiplier; this is the number every end-state choice hinges on.
3. **Free levers before or alongside the purchase** (fleet doc): call scripts through the interpreter
   instead of `./x.sh` (121 → 2.9 ms per novel exec, MEASURED), consolidate MCP children (~0.5 GB/session),
   and cut the hook fork chain.

**If staying all-Apple:** buy the **Mac mini M5 Pro 18C/64GB ($2,899)** or the **M5 Ultra 30C/96GB ($5,499)**.
Avoid the M5 Ultra 256 GB ($10,799, ~$47/slot): at this mix it runs out of CPU long before it uses its RAM.

**End state for 1000 agents:**
- **Hardware:** headless Linux for sessions and tools, with the Mac as cockpit and orchestrator.
  - **2× Threadripper 9980X/256 GB** (~$28–38K): fewer hosts, ECC.
  - **5× Ryzen 9950X/128 GB** (~$18–23K): cheapest. RDIMM costs $26–50/GB against $17–22/GB for UDIMM, so the
    cluster wins on dollars unless RDIMM prices fall.
  - **All-Apple equivalent:** 5–6× M5 Ultra 30C or 8–9× M5 Pro minis ($23–33K). It keeps the toolchain unchanged, but
    every host still pays the macOS spawn and XProtect tax.
- **Gate before buying:** the end-state purchase only makes sense after (a) the pilot confirms the Linux
  multiplier, and (b) someone answers the quota question. 4 Max accounts sustain 6.2–11.0 active sessions. 1000 agents
  is ~150 sessions (brief's ratio), so all of them active needs ~14–24× the current accounts. For mostly-idle
  resident agents the binding constraint is RAM (~0.4 GB/agent → ~400 GB), not CPU.

## 8. Adversarial pass: gaps found and what I did

1. **Agent-to-process mapping is unknown.** In-process subagents vs teammate processes changes RAM by
   up to ~2× (30 claude processes for ~15 sessions today). I kept RAM per *agent* fitted to the measured all-in memory,
   and flagged the 0.2–0.45 GB band.
2. **M1 Max Cinebench baseline (796) may be low.** Ratios are ±20%. The ordering of options does not change.
3. **The Linux multiplier is not measured on the fleet mix.** That is why the next step is a pilot, not a fleet.
4. **Quota, not hardware, binds 1000 *active* agents.** Added §0.5 and §7. This is the gap most likely to make
   the hardware question moot.
5. **Price volatility.** DRAM rose ~5× in a year and Apple raised prices in June 2026. Every RAM-heavy row could move ±30%
   within a quarter.
6. **Some figures come from search-engine summaries, not fetched pages.** Treat these as lower confidence:
   - Cinebench: M5 Ultra 3,701, TR 9980X 6,632, 9950X 2,340, M5 Max 2,073.
   - System76 $14,264.
   - EPYC street price.
   - Ryzen 9950X $434.
   The Apple prices and the M5/M6 Geekbench 6 numbers were fetched directly (Apple store JSON, EveryMac).
7. **Not checked:** power and noise, 10GbE networking for a mini cluster, and Linux headless Chrome memory (likely
   lower than macOS Chrome, which is unmeasured). None of these would reorder the options.
