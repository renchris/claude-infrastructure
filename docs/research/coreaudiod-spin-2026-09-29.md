# coreaudiod at ~200% CPU, day after day — 2026-09-29

## Verdict

**Mechanism (conviction 80%).** Under CPU starvation, coreaudiod stops tearing down client IO
contexts. Each leaked context keeps its "IO running" power assertion and stays registered until the
daemon restarts. Once the daemon is in that state, every new client start leaks about 7 more
(1 speaker context plus 6 `contextN`), whatever the load. Our notification chimes are the main
source of new client starts: 85% of the contexts leaked on the last daemon were created within 3 s
of a logged `afplay`. The count only climbs: **5,117 held when pid 391 was restarted (Sep 24) and
4,641 when pid 36954 was restarted (Sep 29)**, the oldest held since boot. CPU follows the count,
because the IO thread walks the client list every cycle, and each overload it misses triggers a
Swift-formatted analytics report. The operator's restart dropped CPU to 0%, and the fresh daemon has
held 0 contexts since.

**The leak is a latch, not a per-play rate.** On daemon 36954, 3 of 2,553 plays leaked (0.1%) before
the latch, at every load. After it, 553 of 599 leaked (92%). The latch fired at 2026-09-29 00:18:51,
in the burstiest minute of the whole log (13 chimes, 4 in one second at 00:22:09), at load ~75.
Daemon 391's onset (Sep 24 16:00) was the headless-harness burst of ~16 afplay/min. Checked live on
the fresh daemon: 0 contexts at load 77 and again at load 112 with ~100 chimes since the restart but
no burst. So the trigger is a burst of new clients while the box is starved. Load alone isn't enough.

**Why it recurs daily.** Heavy fleet periods with bursts of session completions happen daily. Once the
latch trips, every new audio client leaks, nothing ever releases a leaked context, and CPU stays
high after the load drops. A restart is the only thing that resets it. The sound gate limits the
burst side (one chime per 2 s machine-wide at most). The watchdog clears whatever gets through.

**Not the cause (measured):** the Pioneer DJ HAL plug-ins and the Microsoft Teams virtual device
(0 of 108 sampled coreaudiod frames in either report are in any third-party image; the Pioneer
plug-ins own no devices, since no hardware is attached), VoiceInk (a registered client, running=0
in/out), and Dia/WebKit (registered, not running).

**Remedy.**
1. *Clears it (operator, root):* `com.claude.coreaudiod-watchdog`, a system LaunchDaemon that
   restarts coreaudiod when ≥ 1000 contexts are held (or ≥ 300 with ≥ 100% CPU). It never restarts
   while an audio input younger than 3 h is live, and at most once every 30 min. Install:
   `docs/activation/pending-activation/48-coreaudiod-watchdog-install.sh --confirm com.claude.coreaudiod-watchdog`.
2. *Slows it (landed, agent-side):* a machine-wide sound gate in `hooks/notify.sh`. It keeps one clock
   for the whole machine instead of one per session or TMPDIR: completion chimes at most every
   15 s, other chimes every 2 s, stretched to 120 s / 10 s when load ≥ 40 or the detector says the
   daemon is leaking. Replayed on the 13-day play log, it cuts plays by 59% at load ≥ 40 and 32%
   overall. Banners and their own sounds are never gated.
3. *Sees it (landed, agent-side):* `com.claude.coreaudiod-watch`, a user LaunchAgent that runs every
   300 s. It counts held contexts (no root), logs `~/.claude/logs/coreaudiod-watch.jsonl`, sets the
   gate's hot flag, and pages the desk once when the verdict changes from ok to leaking.

Not recommended: removing the Pioneer drivers or Teams device for CPU (no evidence they are
involved), or turning chimes off (the gate cuts the harmful rate and keeps the chimes).

## Evidence

### E1. The two CPU reports (`/Library/Logs/DiagnosticReports/coreaudiod_*.cpu_resource.diag`)

| report | pid | CPU | footprint | heaviest paths |
|---|---|---|---|---|
| 2026-09-24 17:01–17:03 | 391 | 90 s over 144 s (62%) | — | 41/74 samples IO thread `PerformIO` → `ApplyToOutput_ButSkipReferenceStreamOnlyEngines` → `_WriteToStream_Mixable` / `AdjustOutputCountersForOverload`; 31/74 caulk worker → `OverloadReporter::SendAnyPendingOverloadReports` → `AudioAnalyticsSendMessage` → `Dictionary.description` |
| 2026-09-29 00:25–00:27 | 36954 | 90 s over 127 s (71%) | 294.6 → 382.9 MB (+88 MB) | 17/34 overload-report path, 15/34 IO thread `PerformIO` |

Image census over both call trees (`grep -oE '\(([A-Za-z0-9_. -]+) \+'`): CoreAudio, caulk,
AudioAnalytics, libswiftCore, AudioServerDriver(+Transports_IOA2), MacAudio, AudioDSP,
AudioToolboxCore and system libraries only. The overload dictionaries name the device through
`ASDTIOA2LegacyDevice transportType`, which is the built-in speakers. No third-party image appears.

### E2. The leak — `pmset -g log` (the PM ASL store, readable without root)

coreaudiod takes `com.apple.audio.<device>.context.preventuseridlesleep` (or `…contextN…`) while a
context's IO runs, and releases it when IO stops (verified live: one appears mid-`afplay`, gone after).
The log records long holds and, when a process dies, every assertion it still held (`ClientDied`):

| daemon | died | contexts held at death | created |
|---|---|---|---|
| 391 | 2026-09-24 22:42:22 (operator restart) | **5,117** (4,424 `contextN`, 693 speaker) | 16:28 Sep 16 (boot) → 22:24 Sep 24; 4,965 on Sep 24 (16:00 and 19:00 h = the headless-harness incident) |
| 10669 | 2026-09-24 22:55:00 (restart) | 302 in 13 min | while the harness was still running |
| 36954 | 2026-09-29 13:32:36 (operator restart) | **4,641** (4,084 `contextN`, 557 speaker) | 22:55 Sep 24 → 13:29 Sep 29; 4,356 on Sep 29 |

Each held context was a leak, not a live client: `pgrep -x afplay` is 0, and Released `contextN`
holds have p50 = 23 min, p90 = 16 h.

### E3. The leak tracks our chimes and the load

- 3,941 of 4,641 (85%) of pid 36954's leaked contexts were created within ±3 s of a line in
  hooks/notify.sh's play log. At ~600 plays/day, chance would give about 5%.
- Per play on the degraded daemon (Sep 29 11:00–11:08), each `Purr.aiff` was followed within 0–2 s
  by exactly 7 contexts with consecutive ids (e.g. `context32597…32601, 32603` + speaker), none ever
  released. Across Sep 29 03:30–13:00, 30-min buckets run at ≈ 7 leaked per logged play.
- Load (from `~/.claude/logs/qos-census.jsonl`, 30-min buckets since Sep 22) against leaked contexts
  per logged play:

  | 1-min load | buckets | leaked | plays | leaked/play |
  |---|---|---|---|---|
  | < 20 | 105 | 2 | 555 | **0.004** |
  | 20–40 | 73 | 441 | 1,050 | **0.42** |
  | ≥ 40 | 115 | 3,988 | 3,085 | **1.29** |

  Plays are concentrated at high load: load ≥ 40 in 12% of samples, but 39% of all plays.
  This table mixes pre- and post-latch periods. Split by the latch (next bullet), the load effect is
  mostly the latch's timing.
- Latch split on daemon 36954 (a play "leaked" if ≥ 1 context was created within −1…+3 s of it;
  "clustered" if another play was within 5 s):

  | period | clustered | leaked / plays |
  |---|---|---|
  | before 09-29 00:00 | no | 1 / 2,105 |
  | before 09-29 00:00 | yes | 2 / 448 |
  | after | no | 376 / 397 |
  | after | yes | 177 / 202 |

  The first run of 5 consecutive leaking plays is at 00:18:51.

### E4. CPU follows the held count

| moment | held contexts | coreaudiod CPU |
|---|---|---|
| Sep 29 00:25 (load ~75, overload storm) | 475 | 71% avg (report) |
| Sep 24 17:01 | 2,232 | 62% avg (report) |
| Sep 29 13:00 | 4,493 | ~195–200% (operator `ps`) |
| Sep 29 13:32 fresh daemon | 0 | 0% |

Three points, confounded by load at the time, so this is correlational. The stacks explain it
directly: per-cycle output iteration plus analytics formatting that grows with each missed deadline.
This is the weakest link and the reason for 80%, not higher.

### E5. What does NOT reproduce the leak on a healthy daemon

`/tmp/ca-leak-exp.sh` and `/tmp/ca-leak-exp2.sh` ran silent `afplay -v 0`, 10 each: normal exit;
SIGKILL at 50 ms and 200 ms; SIGSTOP then SIGKILL; SIGTERM; and 15 s SIGSTOP then CONT or KILL. All
left **0** contexts held. So an abnormal client death alone does not leak. The leak needs a starved
or already-degraded daemon, which matches E3's load dose-response. Why Apple's HAL leaks in that state
(and why 6 `contextN` per play) is not observable from outside the daemon.

### E6. Client census now — `/tmp/ca-clients.c`

It reads `kAudioHardwarePropertyProcessObjectList` (no root). 26 registered client processes, none
running IO (including VoiceInk, Teams helper, Dia helpers, WebKit.GPU, Hammerspoon). Devices:
built-in mic and speakers, Microsoft Teams Audio (virtual), and a Multi-Output aggregate. No Pioneer
device exists, and the default output is the speakers.

### Corrections to the brief

- "Stale power assertion from a gone afplay pid 15336": the assertion reads `caffeinate asserting on
  behalf of Process ID 93707`, named "caffeinate command-line tool", and `ps -p 15336` is empty. It
  is a mislabeled caffeinate assertion, not evidence that afplay outlives its sound. Wedged afplays do
  occur, though: at 13:25 the old daemon's clients logged `AQMEIO.cpp: timed out` and
  `HALC_ProxyIOContext::IOWorkLoop: skipping cycle due to overload`.
- `docs/research/freeze-2026-08-13.md` saw the same churn in August ("~175 new contexts/hour,
  longest hold 99 h") and filed it as hygiene. It is the mechanism of this spin.
- The unified log keeps almost nothing for coreaudiod itself: no persisted lines before the 13:32
  restart in any window probed. `pmset -g log` is the durable record.

## Re-derive

```bash
pmset -g assertions | grep -c '(coreaudiod).*context.*preventuseridlesleep"'   # held now
~/.claude/scripts/coreaudiod-watch.sh                                          # verdict line
tail ~/.claude/logs/coreaudiod-watch.jsonl                                     # time series
grep -c 'ClientDied PreventUserIdleSystemSleep "com.apple.audio' <(pmset -g log)  # held at past deaths
```

The analysis scripts in this session were inline Python over `pmset -g log` and
`$(getconf DARWIN_USER_TEMP_DIR)cc-notify/claude-notify.log`, bucketed by 30 min and joined to
`qos-census.jsonl` loadavg. The watcher's JSONL now records context count and CPU together every
5 min, which closes E4's correlational gap going forward.
