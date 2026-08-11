# 03 — The enforcing capacity layer vs MCP server children

Audit of `scripts/capacity-alarm.sh`, `hooks/coldcompile-admit.sh`, `bin/cc-ignition-gate`,
`scripts/compressor-sentinel.sh` (+ `scripts/lib/capacity-admit.sh`, the only *refusing* gate they
share a lineage with). Paths relative to `~/Development/claude-infrastructure`. Read-only.
Every number is **MEASURED** on this box at 2026-08-11T05:49Z unless labelled INFERRED.

---

## Verdict

1. **The lead's claim needs splitting.** MCP children's **memory** is counted by no budget that can
   act on it — but MCP children's **process count** *is* counted, by `capacity-alarm` rung 6
   (coalition), which reaches ALARM. Measured: 6 of 7 mcp-named processes sit inside the counted
   `kitty` coalition.
2. **Two of the four subjects are structurally inert right now, for reasons unrelated to MCP.**
   `coldcompile-admit.sh` is registered in **neither** settings file, so `cc-ignition-gate` has never
   been invoked by a hook (2 rows ever in its telemetry, both hand-tests on 2026-08-09). And the
   node-population expression shared by `compressor-sentinel` and `cc-ignition-gate` reads **0** on a
   box with 3 live node processes — because this fleet's node lives behind a **space** in its path.
3. **The count budget that does bind saturates long before 150 sessions**: coalition = 349 procs at
   31 sessions = **11.3 procs/session** ⇒ WARN(500) at ~44 sessions, ALARM(700) at ~62. MCP is ~2% of
   that term. Consolidating MCP moves the coalition arithmetic ~1% and the compressor arithmetic
   0.39% of one trip arm — **neither is the reason to consolidate**; resident bytes are.

---

## A. Who counts what

| Script | Trigger / schedule | Population expression (file:line) | Counts child trees? | MCP evasion point |
|---|---|---|---|---|
| `capacity-alarm.sh` **census** (`sessions`) | launchd `com.claude.capacity-alarm`, `StartInterval 60`, `--quiet`, RunAtLoad 0 | `ps -eo pid=,ppid=,args=` → argv[0] (`$3`) matches `claude-code/bin/claude\.exe$` **or** `node_modules/\.bin/claude$`; a proc whose ppid is in-family is subtracted — `:607-623` | **No.** Session ROOTS only; the subtraction is claude-in-family, so all 202 non-claude descendants fall outside | MCP children never match argv[0] ⇒ **uncounted, and correctly so** — but the per-session constant derived from this census (`PER_MB=636`, `:1065`) therefore excludes MCP entirely |
| `capacity-alarm.sh` **rung 4** (max footprint) | same tick | `top -l 1 -o mem -n 3 -stats pid,mem,command` — `:655-669`; fallback `ps -eo pid=,rss=,comm= \| sort -k2 -nr \| head -3` `:673-676`; WARN-only at `PROC_WARN_GB=3` `:830-836` | No — per-process | Largest MCP proc today is 255 MB; live top-3 is `claude.exe 16 GB · kitty 1.8 GB · WindowServer 1.7 GB`. MCP is **structurally unrankable** here |
| `capacity-alarm.sh` **rung 6** (coalition) | same tick | `ps -Ao pid=,ppid=,comm=` → walk each pid's ppid chain (depth cap 64) to a root whose comm basename ∈ {iTerm2, kitty, ghostty, Ghostty}; report the **largest** — `:707-727`; ALARM ≥700 / WARN ≥500 — `:258-259`, `:853-859` | **Yes — full tree, by COUNT** | **MCP children ARE counted here** (measured 6/7 in `kitty`). The only live term that sees them. Counts procs, never bytes, and never refuses (`:1187-1188`, `:1241`) |
| `capacity-alarm.sh` **rungs 1,2,3,5,7** | same tick | box-wide `vm_stat`/`sysctl`: headroom `:327`, pressure `:639`, segments `:529-548`, swap `:328`, load `:751-764` | n/a (aggregate) | MCP memory lands here **unattributed**, indistinguishable from a session's |
| `compressor-sentinel.sh` **census** | launchd `com.claude.compressor-sentinel`, KeepAlive + RunAtLoad, 10 s tick; census every 6th tick (`CENSUS_EVERY=6` ⇒ 60 s) `:84`, `:762-772` | `ps -axwwo pid=,ppid=,rss=,comm=` → `base = basename($4)`, keep `base ~ /^node/`; emits count, orphans, summed RSS MB, pid list — `:303-312` | Flat node population only; no walk | **Reads 0 today against 3 real node processes** (§B.1). Even when non-zero, `n`/`nrss` feed **no threshold** — log fields only (`:776-781`) |
| `compressor-sentinel.sh` **trip** | every 10 s tick | `classify_breach` `:281-296`: (`seg > limit×15%` **AND** `seg_rate > 600/s`) OR `Δcbu > 640 MB/interval` OR `Δswap > 1024 MB/interval`; needs `STREAK ≥ 2` + 60 s cooldown `:791` | n/a (aggregate sysctl) | MCP heaps contribute to `vm.compressor_bytes_used` anonymously; no MCP-specific path |
| `compressor-sentinel.sh` **actuator** (SIGSTOP) | on trip, armed by the plist (`CC_SENTINEL_ACT=stop`, `ACT_RSS_KB=40960`, `ACT_CAP=400`) | `select_stop_targets` `:328-342`: comm basename `^node`, not claude/claude.exe, **`args !~ /mcp/`** `:336`, rss > floor, **and absent from the previous census** (new-in-60 s cohort) `:338`. Parent-breaker `select_break_parents` `:378-419` marks `args ~ /mcp/` as `protect` `:385` | Parent-breaker is the only tree-aware term — one hop, ppid of cohort members | **Excluded twice**: dropped by the comm test (§B.1), and if that were fixed, by the `/mcp/` argv test. **By design** — SIGSTOP on an MCP child freezes a live session's tool |
| `cc-ignition-gate` **term 1** (incumbent) | only when a caller runs it — §B.2 | `ps -Awwo pid=,etime=,comm=,args=`, argv **anchored at argv[0]** to next-shaped launchers/workers `:134`; age < `SETTLE_S=90` `:186-189` | No | An MCP child is not next-shaped ⇒ never an incumbent (correct) |
| `cc-ignition-gate` **term 2** (burst) | same invocation | `base = basename($3) == "node"` ⇒ `nodes++`; busy when `nodes > BURST_N=100` — `:182-183`, `:193`, `:113` | No — flat count | **Reads 0 today.** Header claims it excludes "claude/mcp processes" `:55-56`, but the only exclusion applied is `CLAUDE_ARGV0_ERE` `:139`/`:177`, which matches *claude launchers only* — MCP node children **would** be counted if the comm test could see them |
| `coldcompile-admit.sh` | PreToolUse(Bash) — **NOT REGISTERED** (§B.2) | n/a — matches the *command string* against `config/coldcompile.patterns` `:129-148` and prepends `<gate> --class <c> ;` `:171-173` | n/a | n/a — the whole arm is inert |
| `scripts/lib/capacity-admit.sh` (**the only refusing gate**) | `hooks/agent-teams-enforce.sh:183` (Agent tool, `CC_ADMIT_LOAD_TERM=off`); `scripts/handoff-fire.sh:3754`; `scripts/boot-resume-launch.sh:265` | Two terms only: `vm.loadavg/hw.ncpu > 2.0` `:186-188` (**off on the Agent path**) and `cc_hw_headroom_gb` = `free+speculative+inactive+purgeable` `:168-181` vs floor **4 GB** `:122` | **No process term of any kind** | MCP memory is inside `vm_stat`'s aggregate, so it *narrows* headroom — the only way any MCP byte reaches a refusal, and only once already resident |

Adjacent count budgets, for completeness: `bin/cc-dispatch:314` `CC_DISPATCH_CEILING=6` counts
**claimed backlog leases**, not processes; `hooks/agent-teams-enforce.sh:384,396` cap **spawn depth**
and **spawns per session**. None reads the process table.

---

## B. The three evasion mechanisms (measured)

### B.1 — The node census reads 0 because this fleet's node path contains a space

Both node counters take the comm column as a **single whitespace-delimited field**
(`compressor-sentinel.sh:306` uses `$4`; `cc-ignition-gate:182` uses `$3`). This fleet's node is fnm's:

```
/Users/chrisren/Library/Application Support/fnm/node-versions/v22.21.1/installation/bin/node
```

`ps -o comm=` prints it in full (92 chars, verified `ps -p 14588 -o comm=`), so the field is
`/Users/chrisren/Library/Application` and its basename is **`Application`**, not `node`.

Measured by running each script's verbatim awk against live `ps`:

| Instrument | Reads | Truth |
|---|---|---|
| basename of the WHOLE comm string | — | **3 node processes** (pids 14588, 49988, 95588; 370 MB) |
| `compressor-sentinel.sh:303-312` census | `0 0 0\|` | 3 |
| `cc-ignition-gate:182-183` burst term | `nodes = 0` | 3 |

This is **documented as deliberate** (`compressor-sentinel.sh:322-327`, `cc-ignition-gate:180-183`:
"a comm containing a space yields a prefix whose basename is not `node`, which drops the row rather
than guessing at it") — under-inclusive on purpose, because a wrongly-SIGSTOPped process costs a
session. The news is the **population share**: on this box every npx/fnm-spawned node carries the
space, so the exclusion is not an edge case, it is the default. History corroborates partial rather
than total blindness: `~/.claude/logs/compressor-sentinel.jsonl` (55,631 rows, 2026-08-05→08-11) has
`n=0` in **12,105** rows and `n ∈ {3..23}` in the rest — the non-zero rows are space-free node paths
(`/opt/homebrew/bin/node` exists and resolves clean).

**Consequence beyond MCP — the bigger finding.** The SIGSTOP actuator selects on the same expression
(`:334`). A `next dev` storm ignited from an agent Bash call inherits the fleet's fnm PATH, so **the
burst the actuator exists to freeze is invisible to it by the same defect**. INFERRED (not
reproducible without igniting a storm), but it follows mechanically from `:334` and is consistent
with `n=0` dominating the log.

### B.2 — The ignition-admission arm is not wired

- `hooks/coldcompile-admit.sh` appears in **no** `settings.json`. Live PreToolUse(Bash) chain
  (byte-identical in `~/.claude/settings.json` and `~/.claude-secondary/settings.json`):
  `curl-gate-scope · validate-bash · git-worktree-guard · keychain-guard · rm-safe-allowlist ·
  ship-rail-push-allow · qos-rewrite`. `grep -c coldcompile` = **0** in both.
- `~/.claude/logs/ignition-gate.jsonl` = **2 rows**, both `2026-08-09T22:1x`, both `verdict:"busy"`,
  `class:"next-dev"` — hand-test signatures, not hook emissions.
- `~/.claude/config/` **does not exist** as a live directory. The hook resolves its table through
  `$0`'s symlink into the checkout (`:112-127`), so this alone would not have broken it — but it
  confirms the arm was never deployed as a unit.
- Gate + hook + table ARE landed (`git ls-tree origin/main` lists all three; commit `8db131c2`) and
  the hook is symlinked into `~/.claude/hooks/`. Landed ≠ enforcing: the enforcing store here is
  `settings.json` (memory: `conclusion-must-reach-the-enforcing-store`).

### B.3 — The `/mcp/` argv exclusion is a substring test, so it protects unevenly

`compressor-sentinel.sh:336` and `:385` exclude any row whose argv contains `mcp`. Today's chains are
covered (`npm exec chrome-devtools-mcp@latest --isolated`; the node child's argv carries
`node_modules/chrome-devtools-mcp/build/src/telemetry/watch`). But the test is a **spelling, not a
class** (memory: `denylist-enumerates-spellings-not-the-class`): an MCP server invoked as
`node /opt/x/dist/server.js` from a space-free node would be **counted, selected, and SIGSTOPped** —
freezing a live session's tool. Latent hazard for candidates B/C/D if the daemon binary is named
without an `mcp` substring.

---

## C. Where each process shape lands, per architecture

| Process shape | capacity-alarm `sessions` | capacity-alarm rung 6 (coalition COUNT) | capacity-admit (headroom, refusing) | sentinel census + actuator | ignition burst term |
|---|---|---|---|---|---|
| **Per-session stdio MCP child** (today) | uncounted (correct) | **counted** — 3 procs/chain, +4 more when Chrome for Testing attaches | counted only as anonymous bytes, after the fact | uncounted (B.1) and excluded (B.3) | uncounted (B.1); would be counted if B.1 were fixed |
| **Ephemeral burst** (candidate B) | uncounted | counted **only if the 60 s tick lands inside the burst** — a 5 s spawn is invisible to a 60 s sampler | counted only if resident at the instant of a spawn decision | census every 60 s ⇒ mostly missed; and `select_stop_targets:338` ("absent from the last census ⇒ it is the burst") makes an ephemeral proc exactly the shape it would target if B.1 were fixed | same 60 s aliasing |
| **Shared localhost daemon under launchd** (C/D) | uncounted | **DROPS OUT** — the ppid chain terminates at launchd, never at a terminal root ⇒ the count falls by 3–9 per consolidated chain while the bytes are unchanged. **Misattribution in the safe-looking direction** | still counted (box-wide) — the one term that stays honest | census counts it if node-named and space-free; actuator excludes it on `/mcp/`, or freezes it if renamed (B.3) | counted (if space-free) — a permanent +1..+N against `BURST_N=100` |
| **Remote / HTTP MCP** (E) | uncounted | uncounted — **zero local processes** (measured: `motion`/`motion-plus` are `type: http` in `~/.claude.json`; no process matches `motion`) | uncounted (correct — no local bytes) | uncounted | uncounted |
| **Zero-MCP** (A) | — | — | — | — | — |

Two asymmetries to carry into the decision:

- **A daemon's memory belongs to the FLEET budget, not to the session that spawned it** — and the
  only term that gets that right is the one that can attribute nothing: `cc_hw_headroom_gb`
  (`capacity-admit.sh:168-181`, box-wide `vm_stat`). Every *attributing* instrument (`sessions`,
  rung 6) is parent-chain based and therefore **loses** the daemon on consolidation.
- **`PER_MB=636` (`capacity-alarm.sh:1065`) is derived from session ROOTS only.** Measured today:
  31 roots = 19,092 MB = **616 MB/root**, plus 2,021 MB across 202 descendants the constant never
  saw. `est. room for: ≥43 more sessions` therefore over-promises whenever MCP is on — the opposite
  direction from what the header argues at `:1047-1049` (true of the root, false of the tree).

---

## D. Q3 — Would consolidating N idle node heaps into 1 daemon relieve the sentinel?

**No, not at any plausible N — by the sentinel's own thresholds.** Arithmetic from live sysctls:

| Quantity | Measured |
|---|---|
| `vm.compressor_segment_limit` | 1,629,615 segments |
| `vm.compressor_segment_buffer_size` | 65,536 B (= 4 pages at this box's 16 KiB page) |
| Pages occupied by compressor | 113,724 ⇒ `segs_in_core` = 28,431 (`:261-266`) = **1.74 % of limit** |
| swap used | 0 ⇒ `segs_swapped` = 0 (`:269-271`) |
| Compression ratio | `input 137.95 GB / compressed 55.40 GB` = **2.49 : 1** |
| Trip level arm (`TRIP_SEG_PCT=15`, `:79`) | 244,442 segments ≈ **15.6 GiB** of compressor-occupied pages — and it fires **only in conjunction** with `seg_rate > 600/s` (`:291`) |

Live MCP resident total = **1,547 MB** across 3 chains. If every byte went idle and compressed:
1,547 / 2.49 = 621 MB ⇒ 621 MB / 64 KiB = **9,478 segments = 0.58 %** of the limit. Consolidating
3 chains → 1 recovers ~⅔ of that = **6,300 segments = 0.39 %** — i.e. **2.6 % of one arm's level
threshold**, and that arm cannot fire alone: the conjunction at `:291` requires a 600 seg/s ramp,
which is a compile storm, not an idle heap.

Scaling (INFERRED, linear in chains): at 150 sessions holding today's 9.7 % MCP-adoption rate
(3 chains / 31 sessions), 15 chains ≈ 7.7 GB resident ≈ 3.1 GB compressed ≈ 47,300 segments =
**2.9 %** — still under the 15 % floor. MCP would have to be fleet-wide (~150 chains ≈ 77 GB) to
matter here, and that exceeds the box's RAM outright. **Headroom, not segments, binds first.**

The sentinel *would* name the chains if it tripped: `top_by_rss` (`:451-466`) ranks by RSS and prints
full argv for the top 30, so the trip snapshot is the one instrument in this layer that can attribute
MCP memory. It simply cannot act on it, and it never fires on it.

---

## E. Q4 — Admission on RESIDENT count vs ACTIVE count

**No gate anywhere admits on a count.** `cc_capacity_admit` (`capacity-admit.sh:259-368`) evaluates
exactly two terms — load-per-core (`:320-329`, **disabled** on the highest-volume surface,
`agent-teams-enforce.sh:183`) and reclaimable headroom (`:349-368`, floor 4 GB `:122`). Neither is a
population. The only count-shaped things in the layer are:

- `cc-ignition-gate` `BURST_N=100` node processes (`:113`, `:193`) — a **resident** count, inert on
  two independent grounds (§B.1, §B.2);
- `capacity-alarm` rung 6, coalition process count (`:853-859`) — a **resident** count that alarms
  and never refuses (`:1241`).

There is **no active-vs-idle discriminator in the enforcing layer at all.** Idleness signals exist
(`hooks/lib/context-econ.sh`, `waiting-recycle.sh`, the live-session registry) but nothing in
`capacity-admit.sh` reads them.

**Where an active-count policy hooks in:** exactly one place, and it already exists.
`cc_capacity_admit()` is the sole predicate on all three spawn surfaces (Agent tool, handoff-fire,
boot-resume). Put the term there, beside the headroom term, so every caller inherits it and no fourth
copy of a `ps` expression is minted (the file's own SHARED TERMS rule, `:70-114`):

```sh
# capacity-admit.sh, after the headroom term (~:368). Fails OPEN like every other term.
cc_hw_agent_procs() {           # -> count of live agent-family processes, or rc 1
  ps -eo pid=,ppid=,args= 2>/dev/null | awk '
    { if ($3 ~ /claude-code\/bin\/claude\.exe$/ || $3 ~ /node_modules\/\.bin\/claude$/) n++ }
    END { if (NR < 2) exit 1; print n + 0 }'
}
```

Same derivation as `capacity-alarm.sh:607-623` (one derivation, not a third copy), with the in-family
ppid subtraction dropped because a gate wants **processes**, not trees. An *active*-count variant
needs a liveness source this layer does not have; the honest interim is a resident count with the
idle-session shed already prescribed at `capacity-alarm.sh:1187-1188`.

---

## F. Forward integration — the minimal enforcing change per candidate

| | Architecture | Minimal enforcing change (script + predicate) | Misattribution risk introduced |
|---|---|---|---|
| **A** | **Zero-MCP** (CLI/skills only) | Nothing to add — one thing to delete: the `args ~ /mcp/` exclusions (`compressor-sentinel.sh:336`, `:385`) then exempt nothing and only widen the actuator's blind spot. **Prerequisite regardless: fix B.1** (`base = basename(whole comm)`), or the actuator stays blind to the fnm-node storm that A does not remove | None. But A removes the *smallest* term (1.5 GB against 19 GB of session RSS) — do not sell it as capacity relief |
| **B** | **Ephemeral on-demand stdio** | `compressor-sentinel.sh:84` — a 60 s census **cannot see a 5 s burst**, and `select_stop_targets:338` would classify every legitimate ephemeral MCP spawn as burst. (a) Keep the exclusion but make it a class test, not a substring: `args ~ /(^\|[/ ])mcp[-_/ ]/ \|\| args ~ /modelcontextprotocol/`. (b) Add a **spawn-rate** term to `cc_capacity_admit` so a tool call that ignites a server is admitted like any other spawn | **HIGH.** A burst landing between two 60 s census ticks is invisible to every counter; its bytes surface in headroom only once resident. B is the shape this layer measures worst |
| **C** | **Always-on shared localhost daemon (Streamable HTTP, launchd)** | Two changes, both required. (1) `capacity-alarm.sh:707-727` — add a **launchd-rooted fleet term** beside the coalition walk, or consolidation silently drops 3–9 procs/chain from the only count budget. Predicate: `fleet_daemon_procs/rss` = descendants of any pid whose **argv** matches the fleet daemon table, with its own WARN/ALARM. (2) `capacity-admit.sh` — a daemon's RSS is a fixed fleet tax, so raise the floor rather than the per-session estimate: `floor = CC_HW_DEFAULT_MIN_HEADROOM_GB + fleet_daemon_gb` | **The named risk, and it is real.** The daemon's memory belongs to the fleet, but every attributing instrument here is parent-chain based and loses it at launchd. Without (1), consolidation makes rung 6 read ~3 % healthier for zero real change |
| **D** | **Socket-activated idle-exit daemon** | Everything in C, plus: the daemon's *absence* must not read as health. Record `fleet_daemon_procs` as **`null` when the socket exists but no process does**, never `0` — the file's own policy for a blind instrument (`:1255`, `:1261`, `:1263`). Presence check: `launchctl print gui/$UID/<label>`; process count 0 then means genuinely idle | **MEDIUM.** Idle-exit makes the population oscillate, so any *rate* term (`seg_rate`, spawn-rate) reads the re-spawn as a burst. Pin the exclusion in `select_stop_targets` on the **launchd label**, not on the string `mcp` |
| **E** | **Remote / cloud-hosted MCP** | **No accounting change needed and none possible** — measured: `motion`/`motion-plus` (`type: http`) have **zero local processes**. What becomes relevant is not memory: `hooks/curl-gate-scope.sh` already sits on the Bash matcher; egress and secret scope move to the front | **LOW for memory, NEW class elsewhere.** A cost disappearing from the memory ledger is not the cost disappearing (latency, quota, egress) |
| **F** | **Status quo, project-scoped stdio only** (today) | Two fixes needed anyway, independent of MCP: (1) `base = basename(entire comm)` in `compressor-sentinel.sh:306` and `cc-ignition-gate:182` — §B.1 is whole-fleet blindness, not an MCP question; (2) **register `coldcompile-admit.sh`** in the PreToolUse(Bash) chain of both settings files, or delete the arm and stop citing it as a backstop. Then for MCP specifically: derive `PER_MB` (`capacity-alarm.sh:1065`) from **tree** RSS — measured 616 MB root + 65 MB descendants ≈ 681 MB/session today | Status quo's own risk: `est. room for ≥N more sessions` currently over-promises |

**Cross-cutting predicate that makes a daemon accountable (C/D/F alike)** — rooted on an **argv
table**, not on parentage, so it survives the launchd reparenting that C introduces:

```sh
# capacity-alarm.sh, beside read_coalition_procs (:707).
read_fleet_daemon_rss_mb() {   # -> "<procs> <rss_mb>", or nothing when ps is unreadable
  ps -Ao pid=,ppid=,rss=,args= 2>/dev/null | awk -v ere="$CC_CAP_FLEET_DAEMON_ERE" '
    NF >= 4 && $1 ~ /^[0-9]+$/ {
      a = ""; for (i = 4; i <= NF; i++) a = a " " $i
      if (a ~ ere) own[$1] = 1
      par[$1] = $2; rss[$1] = $3; pids[++n] = $1 }
    END { for (i = 1; i <= n; i++) { q = pids[i]; d = 0
            while (q != "" && q + 0 > 1 && d < 64) {
              if (q in own) { c++; r += rss[pids[i]]; break }
              q = par[q]; d++ } }
          if (n == 0) exit 1; printf "%d %d\n", c + 0, r / 1024 }'
}
```

---

## G. Adversarial pass — what I nearly got wrong

1. *"MCP children are counted by NO budget."* **Half false.** They are counted by `capacity-alarm`
   rung 6, a real ALARM rung — measured 6/7 mcp-named procs inside the counted `kitty` coalition. The
   true statement is narrower: **no budget counts their BYTES in a way that can attribute or act.**
   Found only by running the coalition walk, not by reading it.
2. *"The `/mcp/` exclusion is why the sentinel ignores them."* **Not the operative reason.** The rows
   never reach that test — they are dropped one line earlier by the comm-basename test (§B.1).
   Removing the exclusion today would change nothing; fixing the basename would change everything,
   including re-arming the hazard the exclusion exists to prevent (§B.3).
3. *"cc-ignition-gate excludes MCP processes."* Its **header says so** (`:55-56`); its **code does
   not** (`:139`, `:177` exclude claude launchers only). Documented and shipped behaviour disagree;
   the shipped behaviour is the safer of the two here.
4. *Assumed the sentinel was running stale bytes* (file mtime 2026-08-10 00:51 > daemon start
   00:44:47). Checked: working tree clean, last **content** commit `77d33bdc` 2026-08-09 22:47 — the
   mtime is a checkout touch. The running daemon carries current logic. Not a landed≠live defect.
5. *Assumed the coalition root was iTerm2* (the threshold's derivation names it). Measured: the only
   live coalition is **kitty** (349–353 procs). `:712` does list kitty, so the rung works — but any
   future terminal outside that four-name list reports **no coalition at all**, and the self-test
   treats an empty read as SKIP (`:956-957`), not FAIL.
6. *Checked one settings file.* This session's config dir is `~/.claude-secondary`; the fleet's is
   `~/.claude`. `coldcompile` is absent from **both** — the inertness is not a per-session artifact.

---

## H. Uncertainties, named

- **Storm-time behaviour of B.1 is INFERRED, not measured.** I did not ignite a `next dev` compile to
  confirm a real storm's workers carry the space-bearing fnm path. 12,105 `n=0` rows plus the live
  3-of-3 miss are strong circumstantial evidence; the decisive test is one `next dev` under the fleet
  PATH with a simultaneous `census()` read.
- **The 9.7 % MCP-adoption rate (3 chains / 31 sessions) is a single sample.** `chrome-devtools` is
  scoped to `reso-management-app/.mcp.json` (`npx chrome-devtools-mcp@latest --isolated`) only; a
  second project adopting it moves the projection linearly.
- **Compression ratio 2.49:1 is box-wide**, not MCP-specific. Idle JS heaps typically compress better
  than the mean, so §D's segment estimate is conservative in the direction that *weakens* the case
  for consolidation-as-compressor-relief.
- **`capacity-alarm` read ALARM during this audit** on the load rung (2.76/core; floors uncalibrated
  per `:1232` — 2.53 was fatal, 5.98 survived). Population figures are unaffected; *rates* may not be
  representative.
- **Chrome-for-Testing attachment is bursty.** Only one of three chains had a browser attached at
  sample time (subtree 1,012 MB vs 393 / 142 MB). Per-chain cost is bimodal, not a mean. Of the
  1,547 MB, ~470 MB is chrome-devtools-mcp's own `telemetry/watch` node child (3 × ~156 MB) — a
  per-chain fixed cost that consolidation would remove outright.
