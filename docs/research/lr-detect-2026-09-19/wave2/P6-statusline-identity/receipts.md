# P6 — statusline identity chip: receipts

**Unit premise (to refute):** *Adding `⌗<pane> <sid8>` left-anchored to `~/.claude/statusline.sh`
is free, renders in 30-col panes, and can be converged.*

**Verdict: PARTIAL.** Free — yes, measured at 0 added subprocesses and −0.2 ms CPU/render.
Renders at 30 cols — yes, but the **glyph choice is refuted**: `⌗` U+2317 is absent from Monaco
(this box's kitty font), which is the *same* coverage failure that already forced two documented
reverts of the circled-digit glyph. Convergeable — **only through `install.sh`**, which
`deploy-live.sh` explicitly says it cannot repair. And the surface is **half-blind on the exact
population this wave is about**: 13 of 26 rate-limit markers have no live telemetry row at all.

Environment: box load 11.35 (`uptime`, 2026-09-19 16:00 local). All timings are on that load.

---

## R1 — The real payload DOES carry `session_id`, `session_name` and `rate_limits` (2.1.260)

Binary: `~/.claude-260/node_modules/@anthropic-ai/claude-code/bin/claude.exe`, version 2.1.260,
GIT_SHA `e51f681183f733dbe9a81bf35921c786ee26dbc6`, BUILD_TIME 2026-09-03T19:41:35Z.

`strings -a -n 8 claude.exe > /tmp/cc260.strings` (330,996 lines). The payload builder `RZt(...)`:

```
return{...fa(w,it),...uo&&{session_name:uo},model:{id:wt,display_name:ti(wt)},
 workspace:{...},version:...,output_style:{name:Yt},cost:{...},
 context_window:xZt(ao,to),exceeds_200k_tokens:ne,...EZt(),fast_mode:pe,
 ...eh(wt)&&{effort:{level:ET(wt,st)}},thinking:{enabled:jt!==!1},
 ...(_o.five_hour||_o.seven_day||_o.spend_limit)&&{rate_limits:_o},
 ...Je&&{vim:...},...At&&{agent:{name:At}},...jn()!==null&&{remote:{session_id:w.id}},
 ...Ke&&{pr:...},...io&&{worktree:{name,path,branch,original_cwd,original_branch}}}
```

`fa(e,n)` (2-arg call) returns:
`{session_id:e.id, transcript_path:bp(e.id), cwd:n, scratchpad_dir:…, prompt_id:HQ()??undefined,
permission_mode:undefined, agent_id:undefined, agent_type:E_(), effort:E}`

`_o` (the rate-limit block), from `go=iM()`:
`{five_hour:{used_percentage:go.five_hour.utilization*100, resets_at:go.five_hour.resets_at},
seven_day:{…}, spend_limit only when Pe()==="gateway"}`

The binary's own shipped schema doc (`/tmp/cc260.strings:279945-280050`) confirms and adds the
conditions that matter:

- `"session_id": "string", // Unique session ID`
- `"session_name": "string", // Optional: Human-readable session name set via /rename`
- `"prompt_id": "string", // Optional: UUID of the prompt being processed`
- `"rate_limits": { // Optional: … Only present for subscribers … **after first API response,
  while at least one window is present**.`
- `"five_hour": { // … **present only while the API reports it and its resets_at has not passed**`

**Consequence.** `session_id` is unconditional and already extracted by the live script
(`~/.claude/statusline.sh:78-88`, `PAY_SID`) — the `sid8` half of the chip costs nothing new.
`session_name` is present only after `/rename`, so it is not a fleet-wide key.
`rate_limits` is *absent* until the first API response and *disappears* once `resets_at` passes,
so it can never be read as "this pane is limited" — it is a utilisation gauge, not a limit flag.

## R2 — The pane id is NOT in the payload; it is in the inherited env (so it is fork-free)

`RZt` has no pane/terminal field, and the schema doc lists none. The live script already reads
`TERM_PROGRAM`, `TERM`, `CLAUDE_CONFIG_DIR`, `CLAUDE_INSTANCE_N` from its inherited environment
(`~/.claude/statusline.sh:339, 349, 421-423`), which proves the statusline command inherits the
pane's env. `~/.zshrc` exports `ITERM_SESSION_ID=w0t0p0:$KITTY_WINDOW_ID` inside kitty
(documented at `~/.claude/statusline.sh:414-419`), so `${KITTY_WINDOW_ID:-}` with
`${ITERM_SESSION_ID##*:}` as fallback resolves the pane with **zero subprocesses**.

## R3 — Cost: 0 added forks, −0.2 ms CPU/render (i.e. free, measured)

Patch applied to a COPY (`statusline-patched.sh`); the live file was never touched.

```
diff statusline-baseline.sh statusline-patched.sh
486c486,496
< echo -e "${GLYPH_PREFIX}${PCT_SEG}${OUTPUT}${RESET}"
---
> ID_SEG=""
> _P6_PANE="${KITTY_WINDOW_ID:-}"
> [ -z "$_P6_PANE" ] && _P6_PANE="${ITERM_SESSION_ID##*:}"
> _P6_SID8="${PAY_SID:0:8}"
> if [ -n "$_P6_PANE" ] || [ -n "$_P6_SID8" ]; then
>     ID_SEG="${NEXT_RING}⌗${NEXT_NUM}${_P6_PANE}${RESET}${GRAY} ${_P6_SID8}${RESET}${GRAY} · ${RESET}"
> fi
> echo -e "${GLYPH_PREFIX}${ID_SEG}${PCT_SEG}${OUTPUT}${RESET}"
```

Fork audit of the added lines: `diff | grep '^>' | grep -nE '\$\(|`|\|'` → **one hit, line 8,
`if [ -n "$_P6_PANE" ] || [ -n "$_P6_SID8" ]`**, which is the shell `||` operator, not a pipe.
**Zero `$(...)`, zero backticks, zero pipelines.**

CPU measured with `resource.getrusage(RUSAGE_CHILDREN)` over 30 renders each, cwd =
`/Users/chrisren/Development/claude-infrastructure`, real payload shape:

```
baseline: wall 56.9 ms/render  cpu 61.4 ms/render
patched:  wall 55.5 ms/render  cpu 61.2 ms/render
```

Three interleaved wall-clock rounds of 30 (same conditions):
`r1 base 59.0 / patch 65.2 · r2 base 62.1 / patch 60.1 · r3 base 56.7 / patch 56.1 ms`
— mean base 59.3, patch 60.5, spread ±3 ms. Delta is inside the noise and the CPU figure (−0.2 ms)
is the one to quote, because the wall figure on a load-11 box is dominated by scheduling.

⚠️ NOTE: zsh's builtin `time` around the same loop reported `0.03s user 0.04s system` for 30
renders (≈2.3 ms/render) — it does not account the subshell's waited children here. The
`getrusage(RUSAGE_CHILDREN)` figure (61 ms) is the correct one; do not quote the zsh number.

## R4 — 30/38/51-column truncation: the chip survives, and costs 16 columns

Rendered both scripts on the payload, stripped SGR/OSC-8 with the binary's own regex
(`$Zt=/\x1b\[[\d;]*m|\x1b\]8;[^\x07\x1b]*(?:\x07|\x1b\\)/g`), width by east-asian-width:

```
baseline  cols=50  '(4) 22% · claude-infrastructure (3cdaa2552) · high'
  @30 '(4) 22% · claude-infrastructur'
  @38 '(4) 22% · claude-infrastructure (3cdaa'
  @51 '(4) 22% · claude-infrastructure (3cdaa2552) · high'

patched   cols=66  '(4) ⌗121 12e163a9 · 22% · claude-infrastructure (3cdaa2552) · high'
  @30 '(4) ⌗121 12e163a9 · 22% · clau'
  @38 '(4) ⌗121 12e163a9 · 22% · claude-infra'
  @51 '(4) ⌗121 12e163a9 · 22% · claude-infrastructure (3c'
```

The chip is fully legible at 30 columns (left-anchored, as designed). **It costs 16 columns and
pushes the existing line from exactly-fitting at 50 to overflowing at 51** — the repo name, sha
and effort are what get clipped. The binary renders a single-line statusline as
`<Text dimColor wrap="truncate">` (`NTe`), so truncation is at the RIGHT edge — the chip is safe,
the tail is what is spent.

## R5 — 🚨 THE GLYPH IS REFUTED: `⌗` U+2317 is not in Monaco, this box's kitty font

```
python3: '⌗' 0x2317 EAW=N  VIEWDATA SQUARE
kitty.conf: font_family Monaco / font_size 18.0 ; $TERM=xterm-kitty
fc-list ':charset=2317' family  →  .LastResort, Apple Symbols, Arial Unicode MS, STIX Two Math, STIXGeneral
```

Monaco coverage probe, with a positive control (`①` U+2460 is the glyph `statusline.sh:400-419`
records as having FAILED in kitty and been reverted, and `·` U+00B7 is in the line today):

```
U+2317 (⌗): Monaco=0      ← the proposed chip glyph
U+2460 (①): Monaco=0      ← POSITIVE CONTROL: known-bad, already reverted twice
U+00b7 (·): Monaco=1      ← in the current line, renders fine
U+2022 (•): Monaco=1
```

U+2317 is EAW **Neutral**, so kitty allots it one cell (unlike ①/➊, which are Ambiguous and get
squeezed) — but Monaco does not contain it, so CoreText substitutes a *proportional* fallback
(Apple Symbols / Arial Unicode MS) into a 1-cell box. That is exactly the downsample mechanism
`~/.claude/statusline.sh:377-398` documents as the reason the circled glyphs were abandoned, and
the operator reverted that on sight, twice (`f6b0f8a3`, `6a8686a4`, `c0970351`, `fbbbbef2`,
`7ab0acb5` — listed in `tests/statusline-identity.bats:25-30`).
**Use a Monaco-covered marker (`#`, U+0023, EAW=Na; or `•` U+2022) — not `⌗`.**

## R6 — `statusLine.refreshInterval` EXISTS in 2.1.260, and the 16-pane cost is ~1 core at 1 Hz

Settings zod schema, verbatim from the binary:

```
statusLine:c({type:k("command"),command:s(),padding:T().optional(),
  refreshInterval:T().min(1).optional().catch(void 0)
    .describe("Re-run the status line command every N seconds in addition to event-driven updates"),
  hideVimModeIndicator:O().optional()…})
```

Runtime: `function STe(w){let H=w?.refreshInterval;return H===void 0?null:Math.max(1,H)*1000}`
and the timer `#b(){…let w=STe(this.#t.statusLine); if(w===null)return; let H=Math.min(oS,w),
ne=()=>{this.#S(); this.#s=this.#e.setTimeout(ne,H)}; …}` with `var oS=2147483647` and a 300 ms
debounce (`wZt=300`) before the command actually executes.

**It is not configured anywhere today:**
```
~/.claude              {"type":"command","command":"~/.claude/statusline.sh"}
~/.claude-next         (same)
~/.claude-secondary    (same)
~/.claude-tertiary     (same)
~/.claude-quaternary   (same)
```

Cost model at the measured 61 ms CPU/render and 12 live panes (`cc-registry`: 12 alive, 19 dead):

| refreshInterval | 12 panes | 16 panes |
|---|---|---|
| 1 s  | 0.73 core | **0.98 core — one core saturated, forever** |
| 10 s | 0.073 core | 0.098 core |
| 30 s | 0.024 core | 0.033 core |

1 s is unaffordable on a box that already sits at load 11. 10–30 s is the affordable band.

**Also found — a free re-render nobody is using.** `#y(w)` schedules a re-render at
`IZt(He) = min(min(rate_limits.*.resets_at)*1000, prompt_cache.expires_at*1000)`, fired at
`w + CZt - Date.now()` with `CZt=1000`. So **every pane already re-renders ~1 s after its 5-hour
window resets**, with no configuration at all. That is a reset-time signal, not a limit-time one.

## R7 — A LIMITED pane DOES re-render after the limit — but the surface is half-blind

Joined all 26 `rate_limit__*` StopFailure markers against `/tmp/cc-telemetry/<sid>.json`
(telemetry is written by the statusline itself, `~/.claude/statusline.sh:100-130`):

```
markers 26 ·  have telemetry 13 · MISSING 13
07e30aeb next3 death=1789849768 telem=1789850098 delta=+330s     ← pid 84167 ALIVE
8843bcf3 next3 death=1789847933 telem=1789851050 delta=+3117s
4bc1159f next3 death=1789848044 telem=1789850108 delta=+2064s
98f02458 next3 death=1789847553 telem=1789851104 delta=+3551s    ← pid 62675 now DEAD
11569d45 next3 death=1789847624 telem=1789851531 delta=+3907s    ← pid 41980 ALIVE, config_dir=.claude-secondary
65186f1f next3 death=1789847861 telem=1789851398 delta=+3537s    ← pid 59379 ALIVE, config_dir=.claude-secondary
e442434c next4 death=1789838839 TELEM-MISSING hist=True
28f07827 next4 death=1789838088 TELEM-MISSING hist=True   (×4 markers)
fff83638 next4 death=1789846085 TELEM-MISSING hist=False
0e2567ee next4 death=1789846089 TELEM-MISSING hist=False
…
```

Two findings:

1. **YES, a limited pane re-renders.** `07e30aeb` is the clean case: limited at 1789849768, its
   statusline wrote telemetry at 1789850098 (**+330 s after the limit**), and its pid 84167 is
   still alive. So the statusline is a LIVE surface on a limited pane — the process keeps
   rendering. But with no `refreshInterval` there is no periodic tick, so the row then goes
   arbitrarily stale (`07e30aeb` is 25 min stale at census time while alive).
   ⚠️ **Do not read the large deltas as post-limit renders.** `11569d45` and `65186f1f` were
   marked on `next3` (`.claude-tertiary`) but their telemetry now reads
   `config_dir=/Users/chrisren/.claude-secondary` — they were **transplanted**, so their fresh
   rows are a recovered session's, not a limited one's.

2. **13 of 26 markers have no telemetry row at all.** Several of those (`e442434c`, `28f07827`,
   `26cd14be`) have a `.hist` sidecar — written by `hooks/lib/context-econ.sh:227,285` from the
   json — so the json existed at some point and is gone now; `fff83638`/`0e2567ee` have neither.
   No deleter was found (`grep -rn 'cc-telemetry\|TELEMETRY_DIR' hooks/*.sh | grep -E '\brm\b|unlink'`
   → no hits), so the CAUSE is **UNMEASURED**. The consequence is measured and is what matters:
   **a statusline/telemetry-derived census answers "which sessions are limited" for at most half
   the population; the StopFailure marker answers for 100% of it.**

## R8 — kitty title and user_vars carry NOTHING about the limit today

```
kitten @ ls --match id:147   (147 = registry row for the limited session 07e30aeb)
  id 147  title '✳ Bottle image review for Studio60 menu'
  user_vars {}
  tab_title '◑ limit-recover optimization'  tab_active True
```

The window title is `✳ <ai title>` — **no session id, no pane state, no limit flag**; a limited
pane is indistinguishable from a working one by title. `user_vars` is **empty**, i.e. nothing on
this machine sets kitty user variables today — the surface exists and is free, but is unused.

Cost of a *matched* query, 3 runs: **53 / 55 / 55 ms** (the brief's ~37 ms figure holds modulo
this box's load 11). An unmatched `kitten @ ls` is ~0.5 s and has timed out at 10 s before.

## R9 — Converging statusline.sh is install.sh-only, and deploy-live says so in words

`install.sh:960`: `copy_file "$REPO_DIR/statusline.sh" "$CONFIG_DIR/statusline.sh"` —
`copy_file()` (`install.sh:219-232`) does `cp` + `chmod +x`, i.e. **a real copy, never a symlink.**

Current state: `diff repo/statusline.sh ~/.claude/statusline.sh` → **IDENTICAL** (no drift today).

`scripts/deploy-live.sh:1310-1333` states the constraint in its own words:

> *"install.sh's COPY classes (githooks/, launchd/\*.plist, **statusline.sh**, bin/it2-wrapper→bin/it2,
> CLAUDE.md) … A copy class has **NO unconditional repairer anywhere on the machine**: install.sh is
> the only one, and it REFUSES a global install from a behind-trunk checkout (install.sh:109-132)"*

and its operator page (`:1394`):

> *"copy-drift: N copy-class file(s) DIFFER from this checkout … all live-STALE … and **NOTHING on
> this path can repair them** (link_refresh owns symlink classes only; install.sh is the sole
> repairer and refuses from a behind-trunk checkout)"*

**Is it agent-runnable?** Yes, indirectly and only on an ADVANCE.
`.claude/CLAUDE.md:35-47` grants the agent `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`
for its own just-landed content, and says the degraded tier *"still runs `install.sh`"*. But
`deploy-live.sh:1770` pins the limit: *"install.sh runs ONLY on the advance path"* — so a
deploy-live tick that finds nothing to advance converges **no** statusline change.
Practical rule: **land the change, then run the granted deploy-live in the same breath**; if the
advance is refused, the statusline change is NOT live and `deploy-parity-assert.sh` will report it
as `COPYSTALE`/`STALE` that nothing automatic will clear.

## R10 — The byte-identity test would NOT block this change

`tests/statusline-identity.bats:55`, verbatim: *"Historical certification. It cannot go red for a
change to statusline.sh, by design."* The suite pins **pre-slim (93720eb8) vs the slim commit
(df6b328f)**, both resolved from git by content — it stopped diffing the working tree in 2026-08-05
precisely because later commits deliberately changed the rendered bytes (the five glyph revisions
listed at `:25-30`). So a new left-anchored segment is not gated by that suite.

---

## What this means for the wave (detection / identification / surfacing only)

1. **Take the `sid8` half — it is genuinely free** (already-extracted `PAY_SID`, 0 forks,
   −0.2 ms CPU) and it is the one thing no other per-pane surface carries: kitty's title has no
   session id and `user_vars` is empty.
2. **Take the pane id from env, not from a shell-out** (`${KITTY_WINDOW_ID:-}` →
   `${ITERM_SESSION_ID##*:}`); that is what keeps it free.
3. **Do not use `⌗`.** Monaco has no U+2317 and the fallback-into-one-cell downsample is the
   documented, twice-reverted failure. `#` is in Monaco and is EAW-narrow.
4. **Budget 16 columns** — the current line already fits exactly at 50 and this pushes it to 66.
5. **The statusline is not the DETECTOR.** It renders after a limit (measured +330 s, pid alive),
   but 13/26 of today's limited sessions have no telemetry row at all, and `rate_limits` vanishes
   from the payload once `resets_at` passes. The StopFailure marker is the 100%-coverage event;
   the statusline chip's job is **IDENTIFICATION** (which pane is which session), not detection.
6. **If a freshness signal is wanted, `statusLine.refreshInterval` exists and is unset** — but
   price it at 61 ms CPU/render: 1 s × 16 panes = ~1 core, permanently. 10–30 s is the band.
7. **Converge dependency:** statusline.sh is a copy class. Land + `CC_DEPLOY_MAX_LAG_COMMITS=0 bash
   scripts/deploy-live.sh` in the same session, and check the advance actually happened — no
   advance, no install.sh, no converge, and nothing else on the machine will repair it.
