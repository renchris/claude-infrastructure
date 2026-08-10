# Axis O — Blind-spot sweep (negative-space slot) — 2026-08-10

Method: 13 read-only probes across resource classes the 14 axes' briefs do not name:
kernel/kexts · system-domain + /Library launchd · BTM/login items · Apple idle/media/index/log
daemon fleet · displays/WindowServer · virtualization · backup (TM + restic) · network/tunnels ·
per-account home duplication · Rosetta · crash-report layer. Every candidate below survived an
explicit "does an existing axis cover this?" pass; rejects listed at the end with the axis that
kills them. All numbers measured this session (snapshot at load-avg 107, 14+ live sessions,
PhysMem 53G used / 5.6G wired / 3.5G compressor, swap 0).

## Candidates (7)

### O-1. Third-party autolaunch fleet — ~1.3 GB resident, in NO census
- **Evidence**: measured `ps` sum **1,306 MB** across the vendor fleet: LibreOffice soffice 326MB
  (arm64, idle-open) · VoiceInk 304MB (likely holds a resident ASR model) · Adobe ×10 procs ≈350MB
  (CCXProcess 109, Desktop Service 66, Core Sync 52, AcrobatResourceSynchronizer 49, helpers) ·
  Razer GameManagerService 95 + Elevation 8.5 · OneDrive 70+22.5 · MonitorControl 40 · Figma agent
  25 · NordVPN helper 19.5 · Pioneer DJ AutoLauncher ×9 ≈14MB · MSTeamsAudioDevice driver 8.5.
  Sources: 18 plists in `/Library/LaunchDaemons`, 10 in `/Library/LaunchAgents` (Pioneer DJM-A9/V10
  + FwUpdateManager, Adobe ×4, Microsoft ×3), BTM login items (sfltool needs admin; launchctl
  `application.*` rows confirm). Plus updater daemon farm: Edge ×4, OneDrive ×2, Teams, Google
  keystone ×3, Adobe ARMDC (interval-run, ~0 resident now).
- **Rosetta rider**: all 9 Pioneer AutoLaunchers are **x86_64-only** (`file` verified) → they alone
  keep oahd (2.4MB) + the AOT translation cache warm. LibreOffice is arm64.
- **Adobe disk rider**: ~/Library/Logs is 1.0GB, of which Adobe 540MB + CreativeCloud 402MB = 94%.
- **Coverage check**: axis B's census line reads "**47 user LaunchAgents; ours ≈ 30**" — B scoped
  itself to `~/Library/LaunchAgents`. The system domain, /Library domains, and BTM are unowned.
  The prespawn negative-space item 2 waives "Chrome/Dia/Adobe ≈ 7.7GB" *operator apps* for
  bottleneck-refute to attribute — that figure is browsers; this 1.3GB tranche is separate,
  autolaunch **residue** with a mechanical fix, not active browsing.
- **Harm**: 1.3GB ≈ 2 marginal sessions (census: claude 8.7GB/14 ≈ 620MB/session).
- **Should own**: B (extend census to system+/Library+BTM domains).
- **First probe**: `sudo sfltool dumpbtm` → per-item `launchctl bootout system/<label>` +
  Login Items disable; re-run the 1,306MB sum command after.

### O-2. Apple media/intelligence fleet runs DURING peak — ~510 MB, doctrine-fed
- **Evidence**: mediaanalysisd **278MB** · suggestd 43 · assistantd 38 · duetexpertd 35 ·
  photoanalysisd 34 · siriactionsd 31 · photolibraryd 24 · itunescloudd 19 · cloudphotod 11
  ≈ **512MB resident at load-avg 107** (i.e., at peak, not idle). Security tranche adjacent:
  syspolicyd 50 + XProtect services ~64.
- **The tell**: Photos library is only **52MB** — mediaanalysisd's 278MB is NOT photo indexing.
  mediaanalysisd serves Live Text/vision OCR on captures; the fleet's own screenshot-verification
  doctrine (memory `feedback-tui-visibility-numbers-first.md`: "screenshot-verify via window-id
  capture") + `com.chrisren.screenshot-clipboard` agent feed it continuously.
- **Doctrine link 2**: `com.claude.caffeinate-floor` + `displaysleep 0` + ~20 stacked caffeinate
  assertions (`pmset -g assertions` measured) = the machine is never asleep and never idle-quiet,
  so DAS idle tasks share RAM/CPU with the 15-session peak instead of running in true idle.
- **Coverage check**: B owns OUR plists' cost (caffeinate-floor, screenshot-clipboard as agents);
  NO axis owns Apple's daemon response to that doctrine. L attributes pressure but its brief
  (QoS/limits/memorystatus) doesn't name the DAS fleet.
- **Should own**: B (system-side consequence of its plists) or L.
- **First probe**: count caffeinate assertions + 24h `log show --predicate 'process ==
  "mediaanalysisd"'` correlation with screenshot events; then decide suppress vs accept.

### O-3. 13 `~/.claude*` homes, 11.3 GB — axis I is scoped to ONE
- **Evidence**: `du` per home: .claude 3.9G · **tertiary 2.2G · secondary 1.7G · quaternary 1.5G**
  (account homes; projects/ = 2.1G + 1.6G + 1.4G = 5.1G transcripts) · version-pinned residue
  .claude-{156,161,170,183,219,220} = **1.35G** · .claude-versions 597M · main projects/ 1.9G.
  Total ≈ 11.3G, of which ~7.0G is transcript stores across 4 account homes.
- **Coverage check**: axis I's brief reads "du by store (**2997-session projects dir**, backups,
  662 plans …)" — singular, the MAIN home. 159 scripts reference the sibling homes (they are live
  account infrastructure — handoff-fire, gen-account-map, kitty-setup), but no retention/compaction
  owner exists for their projects dirs, and the 6 version-pinned homes + .claude-versions are
  dead-track residue. restic archives ONLY `~/.claude/archives/claude-code/` (script line 58).
- **Memory relevance**: mds/mds_stores (667MB, I-owned Spotlight) indexes ALL homes — I's Spotlight
  work under-scopes its corpus if it only meters the main home; session-search-sweep/backfill scan
  cost multiplies per home if pointed at the union.
- **Should own**: I (extend du + retention design to the `~/.claude*` glob; version-home deletion
  decision).
- **First probe**: `du -sh ~/.claude*/projects | sort -rh` + mtime census of the 6 version homes
  (any session in 30d?) → delete or `mdutil`-exempt.

### O-4. WindowServer 1.5 GB footprint on FOUR displays — the lever nobody prices
- **Evidence**: top phys-footprint **1,523MB** vs ps RSS **165MB** — the 1.35GB delta is window
  backing stores/IOSurfaces, invisible to an RSS census. Displays: built-in 3456×2234 XDR + **3×
  5120×2880 5K** @2x. kitty shows the same split (top 1,909MB vs ps 386MB — GPU surfaces).
- **Doctrine link**: split-pane doctrine (memory `feedback-dedicated-split-pane-sessions`, handoff
  `--split-right` default) mandates a VISIBLE pane per parallel track → window/pane count scales
  with session count; each 2x-scaled window multiplies backing cost ×4 vs 1x.
- **Coverage check**: A's census ("64GB decomposition; RSS vs compressed via footprint/vmmap")
  would LIST WindowServer; H owns kitty's own scrollback/pane economics. Neither owns the
  display-count/scaling lever or the marginal-pane backing cost, and an RSS-based census
  under-counts this class ~9×.
- **Should own**: A (attribution incl. footprint-vs-RSS divergence) + H (marginal pane price).
- **First probe**: `sudo footprint $(pgrep WindowServer)` with 3 vs 2 external displays attached;
  count windows (`lsappinfo`) at 15-session steady state.

### O-5. Unified-log + crash-report layer — 2.9 GB store + serial bash segfaults
- **Evidence**: `/private/var/db/diagnostics` **2.3G** + `/private/var/db/uuidtext` **593M** (the
  SYSTEM log store our chatty launchd fleet writes into — distinct from I's "daemon logs" du of
  our file logs). logd RSS 42MB (fine). **80 .ips** in ~/Library/Logs/DiagnosticReports incl. a
  serial **bash crash cluster 08-02→08-05** (bash-2026-08-02-194151.ips …) → ReportCrash +
  osanalyticshelper symbolication bursts at fleet frequency.
- **Coverage check**: I's store list names our logs, not the system store; L's brief names
  memorystatus/panics 14d but not user-domain .ips — the bash cluster is a hook-layer forensic
  signal (F) nobody is reading.
- **Should own**: I (store + emission budget) · F/L (the bash .ips forensics).
- **First probe**: open one bash .ips (crashing frame → which hook/script); `sudo log stats
  --overview` for top emitters; consider per-subsystem `log config` throttles.

### O-6. Two armed latent bombs: Docker 4 GB + a broken-destination Time Machine
- **Evidence**: Docker settings.json: `memoryMiB: 4096, cpus: 5, autoStart: false` — VM not
  running today (0 RAM; vmnetd 4MB resident) but any `docker` invocation seizes 4GB+5 cores.
  TM: destination "Kind: Local" fails to mount (`tmutil latestbackup` → error 18; `listbackups` →
  "No machine directory found for host") AND **zero exclusions**: ~/Development (278 worktrees),
  ~/.claude, ~/.claude-tertiary, ~/.ollama, /private/tmp all `[Included]` (measured). First
  successful mount ⇒ full initial backup of all of it concurrent with the fleet (backupd + page-
  cache flood). Meanwhile real backup coverage = restic weekly of ONE subdir — a data-safety fact
  for the lead, not RAM.
- **Coverage check**: no backup axis exists among the 15; B would see backupd-helper but its brief
  stops at plist cost.
- **Should own**: B (both are launchd-surfaced) or a one-off decision item.
- **First probe**: `tmutil addexclusion` on worktrees/homes/ollama NOW (safe regardless of dest
  fate); then decide destination repair vs `tmutil disable`.

### O-7. Axis-I glob misses (minor, mechanical)
- **Evidence**: `/private/tmp/claude-501` = **643MB / 50 subagent scratch dirs** — I's brief
  enumerates `/tmp/cc-*`, a different glob (claude-501 is the subagent workdir root; disk/page-
  cache only, but unretained). Adobe's 940MB of ~/Library/Logs (O-1 rider) likewise outside I's
  store list.
- **Should own**: I. **First probe**: add both paths to I's du + retention table.

## Rejected after adversarial pass (axis that kills each)
- Dia `agent-server` 83MB + 22 Dia Browser Helpers → A rev-1 explicitly owns browser-process
  attribution (infra-owned profiles vs operator browsing).
- Spotlight family ≈1.0GB (mds_stores 667 + corespotlightd 103 + mds 71 + mdworkers ~150) → I
  "(incl. Spotlight)" — but see O-3: its corpus must include all 13 homes.
- 97 bash / 49 zsh / 44 sleep procs → A owns "the 70 bash"; C owns sleep-loop pollers.
- Network/tunnel class → none present (no tailscaled/cloudflared/ngrok/zerotier; every listener
  attributed: ollama 11434 G/M · Dia 9222+agent-server 51898 A · node 3000/9245/9246 M · figma,
  Adobe 15292, OneDrive, RazerGame O-1 · ControlCenter AirPlay :5000/:7000 + rapportd trivial).
- Kernel: **zero non-Apple kexts** (kmutil), no boot-args; wired 5.6GB normal for 4 displays/GPU →
  A's 64GB decomposition line. maxproc 16000/maxfiles 491520 → L owns limits.
- Swap/sleepimage: 0 used, /System/Volumes/VM empty (hibernatemode 3 moot under caffeinate-floor).
- iCloud (Mobile Documents 18MB) · Photos library 52MB · Wispr Flow NOT resident (176MB on disk
  only) · Zoom daemon not running · coreaudiod 54MB modest (9 Pioneer audio devices registered —
  noted under O-1) · fseventsd 15MB.

## Instrument corrections (for sibling axes)
1. `ps -axo arch=` **silently ignores** the arch keyword on this macOS — prints comm, so
   `grep x86_64` returns a false "no Rosetta procs". Verify by `file` on binaries (Pioneer = x86_64
   proven) — the corrected-instrument-lies-again pattern.
2. **top phys-footprint vs ps RSS diverge ~9×** on graphics-heavy processes (WindowServer 1523 vs
   165MB; kitty 1909 vs 386MB). Any axis summing `ps` RSS under-counts the graphics class; any
   summing top double-counts shared IOSurfaces. State which metric each census row uses.
3. `tmutil destinationinfo` truncated at `head -12` hides mount state; `latestbackup`/`listbackups`
   carry the verdict.

---

# Revision 2 — deduped against the 2026-08-09 scaling-bottlenecks wave (lead steer)

Baseline widened: artifacts 00-13 + CONCURRENCY_PROGRAM S0-S6 + BACKLOG_CONSOLIDATION M1-M6.
Verified coverage by grep, not assumption. Changes vs Rev 1:

## Dropped / re-scoped (prior wave covers)
- **Unified-log STORE (was half of O-5)**: 08-platform-terms (e) measured it — 2.3GB store,
  953 MB/day ingest, verdict "N — retention self-rotates", tripwire logd CPU>20%. DROPPED.
- **syspolicyd/XProtect adjacency**: prior wave's exec-assessment axis owns it. Dropped from O-2's
  security tranche.
- **Spotlight corpus note**: 11-prior-art even carries the mds disable recipe (MacStadium/
  runner-images precedent). Only the multi-home CORPUS gap survives, inside O-3.
- **WindowServer CPU**: 02-render settled it (0.002–0.009 cores/pane attributable; not a wall).
  O-4 is now memory-only.

## Surviving candidates (7) — what BOTH waves miss, with program-row owners

| # | Blind spot | Both-waves check | Size | Owner row | First probe |
|---|---|---|---|---|---|
| O-1 | Third-party autolaunch fleet (system+/Library launchd + BTM) | 01-memory-age line 179 counts a 723MB "stays" bucket (mds_stores/mediaanalysisd/esbuild/Creative) — an age verdict, not an enumeration or a disable lever; axis B census = user domain only | **1,306MB** measured; Pioneer ×9 x86-only keeps Rosetta warm; Adobe also 940MB of ~/Library/Logs | **M3** umbrella, execution = operator pile | `sudo sfltool dumpbtm` → bootout list → re-sum |
| O-2 | Apple DAS fleet × caffeinate-floor doctrine | caffeinate's 1 prior-wave hit = pty attribution (09); the DAS-at-peak interaction unowned | **~510MB** at load-avg 107; mediaanalysisd 278MB vs a **52MB** Photos library ⇒ fed by screenshot-verify doctrine | **M3** | 24h log correlation mediaanalysisd↔screencapture; assertion census |
| O-3 | 13 `~/.claude*` homes | prior-wave hits incidental (paths, 08(l) .claude.json rewrite race — different concern); no du, no retention owner | **11.3GB**; 7.0GB transcripts ×4 account homes; 1.95GB version-pinned residue (.claude-{156..220} + .claude-versions) | axis **I** + **M6** (account↔home mapping is a runtime fact) | mtime census of version homes → delete/exempt |
| O-4 | WindowServer render **MEMORY** | 02-render: CPU measured exhaustively, `backing\|IOSurface\|footprint` = **0 hits** in 02 | top-footprint **1,523MB** vs ps RSS **165MB** — 1.35GB backing invisible to RSS census; kitty same (1,909 vs 386MB). At S6.2's 150-RESIDENT design point, window count is the driver | **S6 Phase E** (render) + M3 | `sudo footprint WindowServer` sampled over pane ramp; occluded-window purge behavior |
| O-5 | Browser-profile/auth duplication layer (NEW, lead steer) | current-wave A owns browser RAM attribution; 07-accounts-api owns quota/API; nobody owns the profile STORE | **Chrome 4.1G** (browsermcp's browser — necessity question if Dia is primary) + **Dia-Recovery-2026-07-09 440M** (13-month residue) + Dia User Data 1.8G (holds the 4 per-account auth profiles) + Dia-Agent 153M | **M6** (one derivation of account↔profile) + I (retention) | is Chrome referenced by any live config? `grep -r chrome ~/.claude/{settings.json,skills/browsermcp}`; then archive/delete Recovery + Chrome |
| O-6 | Armed latents: Docker + Time Machine | Docker **0 hits** both waves; restic **0 hits**; TM substantive hits none | Docker `memoryMiB:4096` armed (off today, vmnetd 4MB); TM dest unmountable + **zero exclusions** over 278 worktrees + all homes + ~/.ollama; **local-snapshot-vs-restic contention today = NONE** (no successful TM backup ever ⇒ no TM snapshots; restic = weekly, one subdir). Real fact: effectively **no working machine backup** | operator pile + M3 tripwire | `tmutil addexclusion` sweep NOW; Docker: leave off, add tripwire on com.docker.backend appearing |
| O-7 | Crash-report STREAM (re-scoped; retention itself = NON-issue, 67MB+1.3MB, Retired empty — lead's retention guess answered in the negative) | `DiagnosticReports\|ReportCrash` = **0 hits** in prior wave; 05-crash-closure covered CC-session crashes, not the .diag layer | Aug 9 in one stream: panics 03:41 + 04:18 (socd), **mds_stores crash 19:29** (1.8MB .diag), git 22:34, node 21:54, bash 15:47 + 80 user .ips (serial bash cluster 08-02→05) — free forensics M3's panic work never reads; ReportCrash bursts at fleet crash frequency | **M3** (its falsifier should consume this stream) | open bash + mds_stores .diag → crashing frames; correlate with panic timestamps |

Minor (axis-I glob extensions, unchanged): /tmp/claude-501 643MB/50 dirs; Adobe logs 940MB.

## Cross-link worth the lead's eye
M3 records "4 kernel watchdog panics in a week." The un-read .diag stream shows the box in
distress the ENTIRE day of Aug 9 (panic 03:41, panic 04:18, mds_stores 19:29, node 21:54,
git 22:34, bash 15:47) — the crash-report layer is the only instrumentation that was watching
during the exact windows M3 cares about, and it is consumed by nothing.
