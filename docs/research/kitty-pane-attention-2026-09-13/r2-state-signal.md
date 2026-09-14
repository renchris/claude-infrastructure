# R2 — Session state signals in claude-infrastructure

Read-only survey, 2026-09-13. Every behavioural claim below was either read out of the code at the
cited `file:line` **or measured live** on the 23-pane fleet running at the time. Measurements are
labelled `MEASURED`.

---

## 0. Headline

**There is already a purpose-built, correct answer to "working or idling", and it is
`hooks/lib/session-busy.sh :: session_busy_live`** (`:318-388`). It is fed by an **event-driven**
turn-boundary store (`hooks/session-beat.sh` on `UserPromptSubmit` + `Stop`) and it already folds in
the **event-driven permission beacon**. `cc-classify` is *not* that answer — it is a reaper-safety
classifier whose idle threshold is **300 s** (`bin/cc-classify:46`), so it cannot see the
working/idle split at all.

The kitty title glyphs are **real, free, zero-cost signal emitted by the Claude Code binary**, with
two hard caveats (§4): a spinner glyph only means anything if you sample it **twice**, and any pane
whose title was ever set by `kitty @ set-window-title` / `kitty @ launch --title` is **permanently
frozen** and silently lies forever.

---

## 1. State-source inventory

| # | Source | file:line | State vocabulary it emits | Event-driven or polled | Freshness | 5-state coverage (a working · b human-wait · c permission · d agent/peer-wait · e dead) |
|---|---|---|---|---|---|---|
| S1 | **`hooks/lib/session-busy.sh :: session_busy_live`** | `:318-321` contract, `:328` impl | `BUSY \| IDLE-ARMED \| IDLE-DEAF \| GONE \| UNKNOWN` + `suspect` qualifier + `src ∈ {beat,job,none,error}` + evidence string (`prompt`, `permission:<age>s/<tool>`, `job <n> <argv>`, `goal continue mail custody`, `pid-<n>`) | **Event-driven** (reads the beat, which is hook-written); the job arm is a `ps` scan at call time | O(1) read of a file written at the last turn boundary | **a ✅ · b ✅ · c ✅ (evidence `permission:`) · d ⚠ partial (`custody` arm only) · e ✅ (`GONE`)** — the only source covering 4.5 of 5 |
| S2 | **`hooks/session-beat.sh`** → `~/.claude/cc-beats/<sid>.json` | write `:113-119`; fields `:5-6`; `kind` `:64`; `who` `:67-73`; `seq`/`operatorT` `:100-110` | `{sid, pane, cwd, pid, lstart, t, kind, who, operatorT, seq}`; `kind ∈ {prompt, stop}`; `who ∈ {operator, auto}` | **EVENT-DRIVEN, both edges.** Registered `UserPromptSubmit → session-beat.sh prompt` and `Stop → session-beat.sh stop` (`~/.claude/settings.json`) | Written at the transition itself. ⚠ `t` is the *transition* time, NOT a heartbeat — `now-t` on a `prompt` beat is **how long the current turn has been running** | **a ✅ (`kind=prompt`) · b ✅ (`kind=stop`) · c ✗ · d ✗ · e ✗ (a frozen `prompt` beat from a dead session is the one measured false-BUSY, `session-busy.sh:38-41`)** |
| S3 | **`hooks/cc-permission-beacon.sh`** → `/tmp/cc-permission-pending/<sid>.json` (+ `.beacon-alive` heartbeat) | header `:1-45`; write mode; registered on `PermissionRequest` (`~/.claude/settings.json:625,661`), cleared on `PostToolUse`/`Stop`/`SessionEnd`/`PostToolUseFailure` | Payload `{ts, tool_name, tool_input, cwd, tool_use_id}`; presence = blocked | **EVENT-DRIVEN**, both edges (`PermissionRequest` / `Stop`) | Exact. Payload is **harness-authored ⇒ unspoofable** | **c ✅ — the ONLY positive evidence of (c) anywhere.** Nothing else. |
| S4 | **`bin/cc-classify`** | causes at `:763, 780, 786, 806, 842, 849, 883, 894, 942, 953, 974, 985, 994, 997, 1006, 1018, 1026, 1028, 1039, 1041, 1050, 1056` | **15 causes**: `crashed · blocked-on-permission · rate-limited · safeguard-blocked · livelocked · active · task-less · owned-wait · handed-off-lead · coordination-hang · coordination-abandoned · finished-teammate · finished · finished-operator · finished-shared-review` | **Polled** (scans transcripts + git + ps) | `IDLE_S=300` (`:46`) — "active" means *last assistant turn < 5 min*, not *turning now* | **a ✗ (conflated with b under 300 s) · b ⚠ (`owned-wait`, but same label as d) · c ✅ (`blocked-on-permission`, reads S3) · d ⚠ (`owned-wait` again) · e ✅ (`crashed`)** |
| S5 | **Statusline telemetry** `~/.claude/statusline.sh:108-140` → `/tmp/cc-telemetry/<sid>.json` (0700) | write block `:108-140`; explicit staleness caveat `:98-103` | `{sid, pid, cwd, config_dir, context used/remaining/window, effort}` | **Polled by construction** — written on every TUI redraw | ⚠ *"a session inside ONE long operation, or genuinely hung, renders ZERO times and its telemetry goes arbitrarily stale WHILE ALIVE"* (`:98-101`) | **a ⚠ (proxy) · b ⚠ · c ✗ · d ✗ · e ⚠ (`pid` field is the liveness leg)**. MEASURED: freezes at Stop — `telem_age ≈ beat_age` on 6/6 `kind=stop` panes (255/257, 11976/11977, 15090/15091, 3637/3638, 1191/1192, 0/1). Also **no row at all** for `--resume`d panes lacking jq on PATH (`:41-49`) |
| S6 | **Pane registry** `~/.claude/cc-registry/<paneUUID>.json`, written by `hooks/session-register.sh` (SessionStart) / removed by `session-deregister.sh` (SessionEnd) | `cc-sessions:5-12`; `surface` field `session-register.sh:140-145` | `{paneUUID, name, cwd, account, pid, startedAt, session_id, surface ∈ {pane,headless}, lstart}` | Event-driven **birth/death only** | Birth-accurate; dead rows swept lazily on read by `kill -0` + `it2 session list` | **e ✅ only.** MEASURED: `paneUUID` is literally the **kitty window id** (`"324"`), so registry ⇄ kitty title joins directly with no mapping layer |
| S7 | **`bin/cc-sessions`** | `:5-12`, `:28-48` | table / `--json` / `--names` / `--offbox`; off-box rows carry `kind=offbox` + `UNKNOWN` | Polled read + lazy sweep | live | **e ✅** (sweeps dead); no working/idle notion |
| S8 | **`bin/cc-wait`** → `~/.claude/wait-contracts/*.json` | header `:1-22`; read by `cc-classify:523 open_wait_contract` | `{waiter, waitee, expected-signal, deadline, on-timeout, status ∈ {OPEN,CLOSED}}` | Written **before** a block | durable | **d ✅ by design — but DEAD IN PRACTICE.** MEASURED: 64 files, **0 with `status:"OPEN"`**, newest **Aug 11 (33 d old)**; the only in-tree callers are `scripts/wait-contract-lint.sh` and its own selftest. `cc-classify:523` reads a store nothing writes. |
| S9 | **`bin/cc-custody`** → `~/.claude/autonomy/custody/<cwd-key>.jsonl` | `:13`, `:65`; folded into the rung at `scripts/wrap-ledger.sh:994-1045` | events `open \| return \| abandon` keyed on the **firing cwd** | Event-driven at fire / return | durable, **LIVE** (MEASURED: rows dated 2026-09-13) | **d ✅ for fired-peer panes only.** Keyed on cwd, not session; says a debt exists, not that you are idle |
| S10 | **`bin/cc-wedge-watch`** | exit codes `:8-14` | `0 ENGAGED · 3 WEDGED · 4 NOT-APPLICABLE · 2 usage` | Polled, one-shot per spawned pane | at call | **e ✅ (startup-modal wedge)**; blind to steady-state idle |
| S11 | **`hooks/lib/engagement.sh`** | `:1-60` | `cc_engaged_pane` / `cc_engaged_sid` → engaged / `no-registry-row` / not-engaged | Polled | at call | Answers *"did it ever start?"*, not *"is it working?"* |
| S12 | **`bin/cc-husk-sweep`** | `verdict_of` `:171-173` | `RESUME \| DONE \| UNKNOWN` × `DEATH` × `CLOSE` | Polled | at call | **e ✅** — dead session under a bare shell |
| S13 | **`hooks/lead-crash-watchdog.sh`** | `pane_verdict_settle` `:1185`; headlines `:1238, :1252` | `closed \| relaunched \| shell \| unknown`; paints `✅ CLOSED CLEANLY` / `⛔ KILLED` into the pane's tty | Detached daemon armed at `SessionStart` | polls until the pane settles | **e ✅** — the only source that writes its verdict where the operator looks |
| S14 | **`scripts/wrap-ledger.sh`** | `--busy` `:13`, `:2208`; rung logic | rungs `⛔ 📤 🔧 📦 🚀 👤 ✅`; `--busy` delegates **entirely** to S1 (`:1936-1945`) | Polled | at call | Rung is about *work state*, not *session state* — `:1926` says so explicitly: *"FIELDS, NEVER A RUNG: busy-ness is orthogonal to the ladder"* |
| S15 | **`hooks/operator-readout.sh`** | `:1502-1508` | Renders S1's sentence verbatim; *"The SENTENCE is composed by `session-busy.sh`, not here"* | Stop hook | at Stop | Consumer of S1, not an independent source |
| S16 | **`hooks/mailbox-drain.sh` / `session-continue.sh` / `cc-notify` / `cc-await-ping`** | drain `:1-30`; continue `:584-731`; notify verdicts `:101` | delivery verdicts (`delivered`, `mailbox-only`, `target-not-live`, `no-watcher`, `wake-path-armed`, `stale-beat`) | Hook-driven | at call | **No idle/working verdict.** They consume the beat (`cc-await-ping --idle-scoped`, `--sid`) but emit *delivery* state |
| S17 | **kitty window title glyph** (Claude Code's own OSC) | see §4 | `✳` · `◐` · `◑` (no `◒`/`◓` — MEASURED, 40 samples × 23 panes) | **Pushed by the binary**, read by polling `kitty @ ls` | sub-second while animating; **permanently frozen** after any `set-window-title` | **a ✅ (animating) · b ✅ (`✳`) · c ✗ (COLLIDES with b — MEASURED) · d ✗ · e ⚠ (window gone)** |

---

## 2. `bin/cc-classify` — full contract

**Invocation** `cc-classify <sid|paneUUID|name> [--json]` · `--all [--json]` · `selftest`
(`:5-7`). Enumerates via `cc-sessions` (`:45`), so it inherits that tool's dead-row sweep.

**Inputs** (all durable, `never file mtime alone` — `:40-41`):
- registry entry: `session_id, pid, cwd, paneUUID, name, startedAt` (`:754-759`)
- transcript `.jsonl` → `last_assistant_ts` (`:221`, excludes `isSidechain` and `isApiErrorMessage`),
  `turn_census` (`:241`), `livelock_census` (`:271`), `recent_api_limit` (`:303`),
  `safeguard_blocked` (`:324`), `handoff_fired` (`:361`), `tool_in_flight` (`:386`),
  `last_interactive_epoch` (`:636`, via `hooks/lib/cc-interactive.sh`)
- `/tmp/cc-permission-pending/<sid>.json` + `.beacon-alive` → `permpend_state` (`:691`)
- `~/.claude/wait-contracts/*.json` → `open_wait_contract` (`:523`) **[dead store — see S8]**
- `~/.claude/cc-roles/desk` → `is_desk_role` (`:541`)
- `~/.claude/cc-fired/` stamps → `fired_peer` (`:552`), `find_fired_successor_stamp` (`:602`)
- `$HOME/.claude*/teams` configs → `team_live_member` (`:479`), `team_has_real_members` (`:513`)
- git: `work_landed` (`:646`, landed-by-CONTENT vs `origin/main`)
- `ps`/`kill -0`: `alive` (`:205`), `pid_lstart` (`:206`)

**Output** — JSON objects with keys
`name, paneUUID, account, cwd, pid, startedAt, session_id, cause, idle_s, work_landed, lstart, blocked_model, refusal, successor, detail` (MEASURED from `--all --json`).

**The 15 causes, in ladder order** (exactly one per session; first match wins):

| order | cause | line | meaning | reapable |
|---|---|---|---|---|
| 1 | `crashed` | `:763` | owning pid not alive | never (surface) |
| 1.5 | `blocked-on-permission` | `:780` | live beacon names this sid | never |
| 2 | `rate-limited` | `:786` | structured usage-cap API error in tail | never |
| 2.5 | `safeguard-blocked` | `:806` | model content-refusal is the tail's terminal event | never |
| 3a | `livelocked` | `:842` | ≤2 distinct assistant texts over ≥900 s / ≥8 turns | never (surface) |
| 3b | `active` | `:849` | last assistant turn **< 300 s** | never |
| 3c | `task-less` | `:883` | booted ≥1800 s ago, **zero** assistant turns ever | never (surface) |
| 3d | `active` (fail-safe) | `:894` | no readable assistant ts — cannot prove idle | never |
| 4a | `owned-wait` | `:942` | `cc-interactive.sh` unresolvable ⇒ adoption-UNKNOWN | never |
| 4b | `owned-wait` | `:953` | real operator prompt < 21600 s ago (operator-adopted) | never |
| 4c | `handed-off-lead` | `:974` | fired `/handoff` + live `firedBy`-stamped successor | iff landed |
| 4.5 | `active` | `:985` | trailing `tool_use` with no matching `tool_result` | never |
| 4.6a | `owned-wait` | `:994` | an **OPEN wait-contract** names this sid as waiter | never |
| 4.6b | `owned-wait` | `:997` | `cc-roles/desk` resolves to this session | never |
| 5 | `finished-teammate` | `:1006` | spawner-stamped fired worker in a worktree, idle | iff landed |
| 6a | `owned-wait` | `:1018` | lead of a team with ≥1 live member | never |
| 6b | `coordination-abandoned` | `:1026` | idle > 7200 s, partner dead, live co-cwd owner | reapable |
| 6c | `coordination-hang` | `:1028` | lead of a team, **no** live member | never (surface) |
| 7 | `finished` | `:1039` | stamped worker, idle, clean & 0-ahead of trunk | reapable |
| 8 | `finished-operator` | `:1041` | same but operator-launched (no stamp) | never (surface) |
| 9 | `finished-shared-review` | `:1050` | own commits landed, tree dirty, live co-cwd sibling | never |
| 10 | `owned-wait` (default) | `:1056` | everything else | never |

**Blind-downgrade**: if the beacon subsystem is unobservable, the four reapable causes are rewritten
to `owned-wait` (`PERMPEND_REAPABLE_RE`, `:745-749`).

**Verdict for this brief.** cc-classify is a *reaping-safety* arbiter. Its `active` bucket spans
"typing right now" and "idle 4 min 59 s"; its `owned-wait` bucket spans operator-wait, peer-wait,
desk-role, unknown-adoption and the catch-all default. **It cannot answer (a) vs (b), and it
deliberately collapses (b) and (d) into one label.** MEASURED live: 17 sessions classified,
14 × `active`, 2 × `owned-wait`, and the two panes whose composers were provably empty
(265 idle 2.1 h, 276 idle 257 s) came back `owned-wait` and **`active`** respectively.

---

## 3. The beat store (`~/.claude/cc-beats/<sid>.json`)

`hooks/session-beat.sh` — **the single most valuable primitive here.**

- Registered twice in `~/.claude/settings.json`: `UserPromptSubmit → session-beat.sh prompt`,
  `Stop → session-beat.sh stop`.
- Fields (`:113-119`): `sid · pane · cwd · pid · lstart · t · kind · who · operatorT · seq`.
- `kind=prompt` ⇒ **a turn just started**. `kind=stop` ⇒ **the turn just ended**.
- `who` (`:67-73`): `operator` unless the prompt matches `CC_CLASSIFY_AUTO_RX`
  (`^<task-notification>|^<local-command-stdout>|^Stop hook feedback:|^\[Request interrupted|^⟳|^⚑|^⚠|^⛔`)
  — i.e. **our own auto-drive re-prompts are excluded**, so a self-driving session cannot
  fake operator presence.
- `operatorT` is a sticky high-water mark (`:110`); `seq` is monotone (`:107`).
- Identity is `(pid, lstart)` with `TZ=UTC` pinned (`:76-93`) — a recycled pid cannot masquerade.
- Fail-open: backgrounded under a 3 s hard timeout, `exit 0` always (`:120-131`). Kill switch `CC_BEAT=off`.

**Two measured caveats you must design around:**
1. **`now - t` is not staleness.** On a `kind=prompt` beat it is *how long the current turn has been
   running*, which is unbounded on a healthy session. `bin/cc-await-ping:954` names beat-kind a
   refuted discriminator for *liveness* for exactly this reason; `session-busy.sh` uses it
   positively for *busy-ness* and adds a `kill -0` + `lstart` leg to catch GONE.
2. **Subagents write no beat.** MEASURED: 6 `deep-research` panes (318–324) had registry rows and
   fresh telemetry but **no beat file at all** — `UserPromptSubmit`/`Stop` do not fire for them.
   Coverage measured by A10 and quoted at `session-busy.sh:15-16`: **beat 25/27 vs telemetry 19/27**.

---

## 4. CRITICAL QUESTION 1 — the title glyphs

### Who writes them
**Claude Code's own binary**, via an OSC title escape. Not this repo.

- `bin/kitty-pane-menu:277-281` states it plainly: *"Claude Code's own busy/idle glyphs. Matched by
  SHAPE, never by an enumerated `✳ ◐ ◑` list — that set belongs to Claude Code… `◐ X` and `◑ X` are
  ONE pane sampled seconds apart."*
- `docs/research/R6-observability.md:185` records `ESC]0;✳ Claude Code` captured off the wire.
- The glyph strings are **not extractable** from the 189 MB compiled `claude.exe`
  (`strings | grep` returns nothing for `◐◑✳`, while ordinary UI strings like `esc to interrupt`
  *are* present) — so the alphabet below is established **empirically**, not from the binary.

### The alphabet — MEASURED, 40 samples @ 0.25 s × 23 panes, plus a 150 s transition watch

**Exactly three glyphs. `◒` and `◓` never occur.**

| glyph | meaning | evidence |
|---|---|---|
| `✳` (U+2733) | **static — the top-level agent loop is NOT turning** | panes 265 & 276 held it for 40/40 samples while provably idle (composer empty, `kind=stop`, 2.1 h / 4 min) |
| `◐` ⇄ `◑` (U+25D0/U+25D1) | **spinner, ~0.75–0.8 s period — the loop IS turning** | the 6 live `deep-research` panes alternated continuously for the whole window |

**The transition is the proof.** From the 150 s watch, pane 315:

```
 51.30 TITLE 315  '✳' -> '◑ Seedance 2.5 BytePlus US custome'
 51.30 BEAT  pane=315 kind=prompt who=operator seq=3     ← same 0.3 s tick
 ...
 89.13 BEAT  pane=315 kind=stop   who=auto     seq=4
 99.04 TITLE 315  '◐' -> '✳ Seedance 2.5 BytePlus US custome'   ← ~10 s after Stop
```

The `✳ → ◑` flip is **simultaneous with the `kind=prompt` beat**. The return to `✳` lags the `stop`
beat by ~10 s — the Stop hook chain (13 hooks) runs first. Reproduced identically on pane 129.

### Is it free signal? — **Yes, and it is currently 100 % unused.**

- Nothing in `bin/`, `hooks/` or `scripts/` reads a kitty title as state. The only toucher is
  `kitty-pane-menu`, which **strips** it (`:277`).
- It costs one `kitty @ ls` for the **whole fleet** — and `~/.claude/bin/it2 session list --json`
  (already called by `cc-sessions` on every invocation for the liveness sweep) is a kitty shim that
  **already returns the title with the glyph in it** (`"title": "✳ Vista Real…"`). The signal is
  literally being fetched and discarded today.
- `paneUUID` in the registry **is** the kitty window id, so the join is free.

### Three caveats that make a naive reading wrong

1. 🚨 **A frozen spinner is NOT "working".** You must sample **twice**, ≥0.4 s apart, and treat
   *change* as the signal. MEASURED cross-tab of glyph vs `session_busy_live`: of 8 panes showing a
   frozen `◐`/`◑`, **2 were `IDLE-DEAF`** (312, 316). One sample is a coin flip.

2. 🚨 **Any `set-window-title` freezes the pane forever.** kitty's own help, verbatim:
   > *"By default, the title will be permanently changed and **programs running in the window will
   > not be able to change it again**. If you want to allow other programs to change it afterwards,
   > use `--temporary`."*

   This repo already knows — `scripts/limit-recover/lr-lib.sh:340` and `lr-handoff.sh:749` both say
   *"No `--title`: it is sticky and would freeze the `✳`/`◐` liveness glyph"*. But
   **`bin/kitty-split-launch.sh:148` passes `--title` to `kitty @ launch` unconditionally**, and
   `bin/cc-offload:874` uses it (`--title "cloud"`). MEASURED: 7 of 23 live panes carried a
   glyph-less sticky title (`resumed-2d71c6d8`, `kitty-probe-A/B/C`, `r5probe`, …) and are
   permanently dark to this signal.

3. 🚨 **`✳` does NOT separate (b) from (c).** *This is the adversarial finding.* A pane blocked on a
   permission prompt shows **`✳`**, byte-identical to idle-at-prompt. MEASURED twice on pane 129
   with the beacon store sampled in the same tick:
   ```
   28.26 BLOCKED: eab98191(pane 129 glyph=✳)
   55.79 BLOCKED: eab98191(pane 129 glyph=✳)
   ```
   Semantically defensible (both are "waiting for the human"), but for the 5-state taxonomy the
   glyph collapses (b) and (c). The permission beacon is the only discriminator.

---

## 5. CRITICAL QUESTION 2 — event-driven working↔idle transitions

**Yes. Both edges exist, are registered, and are firing today.**

| transition | hook event | consumer registered | writes |
|---|---|---|---|
| **→ idle** (turn ends, control returns to the human) | `Stop` | `hooks/session-beat.sh stop` | `cc-beats/<sid>.json` `kind=stop` |
| **→ working** (human or auto-drive submits) | `UserPromptSubmit` | `hooks/session-beat.sh prompt` | `cc-beats/<sid>.json` `kind=prompt`, `who=operator\|auto` |
| **→ blocked on human** | `PermissionRequest` | `hooks/cc-permission-beacon.sh write` | `/tmp/cc-permission-pending/<sid>.json` |
| **→ unblocked** | `PostToolUse` / `Stop` / `SessionEnd` / `PostToolUseFailure` | `cc-permission-beacon.sh clear` | removes the beacon |
| **→ dead** | `SessionEnd` | `session-deregister.sh`, `live-session-registry.sh` | removes the registry row |

Everything else on the box is polled. Note `Stop` fires 13 hooks, so the true idle instant lags the
`stop` beat by the hook-chain duration (MEASURED ≈10 s on pane 315).

**The one free event that is built but NOT wired: `SubagentStop`.**
`hooks/subagent-stop.sh` exists and `migrations/0014-subagent-stop-registration.sh` is the
registration step — **staged and unrun**. `:12` records: *"`.hooks.SubagentStop` is ABSENT from all"*
config dirs, and I confirmed that again today by dumping every hook array from
`~/.claude/settings.json`. That is a ready-made event-driven "a background agent just finished"
edge, one migration away.

---

## 6. CRITICAL QUESTION 3 — "wants the human" vs "waiting on an agent/workflow/peer"

**Honest answer: nothing on the box distinguishes these reliably today, and the one mechanism built
for it has no live producer.**

What exists, and what each actually covers:

| mechanism | covers | live? |
|---|---|---|
| `session-busy.sh :: sb_idle_arms` (`:282-305`) → arms `goal · continue · mail · custody` | Separates **IDLE-ARMED** ("something will wake me") from **IDLE-DEAF** ("I will sit here forever"). `custody` is the fired-**peer** arm | ✅ live |
| `bin/cc-custody` (`:13, :65`), folded into the rung at `wrap-ledger.sh:994-1045` | A fired peer with `--notify-back` armed owes a return, keyed on the firing **cwd** | ✅ live (rows dated today) |
| `bin/cc-wait` → `~/.claude/wait-contracts/*.json`, read by `cc-classify:523` | The *designed* answer: a durable `{waiter, waitee, signal, deadline, on-timeout}` contract written **before** the block | ❌ **DEAD** — 0 `OPEN`, newest Aug 11, no production caller |
| `cc-classify` team-config arm (`:1018` / `:1028`) | Lead of a team with ≥1 live `--agent-name` process ⇒ `owned-wait`; none alive ⇒ `coordination-hang` | ✅ live, but only for **Agent-Teams** teammates |
| `sb_busy_jobs` (`session-busy.sh:195+`) | A descendant process of mine is executing | ✅ live, but **over-attributes in a shared checkout** — MEASURED: panes 317/318/319 all reported the *same* sibling `bats-exec-test` as their own job, because the arm scopes by cwd |

**The concrete gap.** A lead sitting on 6 in-process subagents is, to every sensor here:
`kind=stop` (idle), telemetry frozen, `✳`-or-frozen-glyph, `cc-classify: active`. MEASURED on pane
317 (the session that briefed me) and pane 316: both showed `⏺ main` + a list of running `◯` agents
on screen, both had `kind=stop`, and `session_busy_live` returned **`BUSY … job`** for 317 only
because `cc-pane-runner` / `bats` processes happened to be in its cwd — which is an accident, not a
contract. Pane 316, with the same on-screen agent list, returned **`IDLE-DEAF`**.

There is **no arm for in-process subagents and none for Dynamic Workflows.** The cheapest closure is
wiring `SubagentStop` (§5) plus a `subagents` arm in `sb_idle_arms`.

---

## 7. Best source per state (the recommendation)

| state | best source | how to read it | confidence |
|---|---|---|---|
| **(a) actively working** | `session_busy_live` → `BUSY`, `src=beat`, evidence `prompt` | rc 0; the `suspect=1` qualifier (transcript mtime > 900 s) is the wedge flag | High |
| **(b) idle, wants the human** | `session_busy_live` → `IDLE-DEAF` (+ `IDLE-ARMED` if something will wake it) | Cross-check with the title glyph `✳` for a zero-cost fleet-wide confirmation | High |
| **(c) blocked on a permission prompt** | `/tmp/cc-permission-pending/<sid>.json` — surfaced by `session_busy_live` as `BUSY … permission:<age>s/<tool>` | Must also check `.beacon-alive` exists, else the absence is *blindness*, not an all-clear | High |
| **(d) waiting on agent / workflow / peer** | **Nothing adequate.** Best available: `IDLE-ARMED … custody` (fired peers only) + `cc-classify owned-wait` via team-config (teammates only) | Treat as an open gap | **Low** |
| **(e) dead / husk** | `session_busy_live` → `GONE` (beat pid dead + `lstart` mismatch); then `bin/cc-husk-sweep` for the disposition (`RESUME \| DONE \| UNKNOWN`) | `lead-crash-watchdog.sh:1238/:1252` is the only thing that paints the verdict where the operator looks | High |

**Ready-to-use one-liner** (`scripts/wrap-ledger.sh:13, :2208`):
`wrap-ledger.sh --busy` → one rendered sentence, composed by `session-busy.sh:417-427`, already the
shared composer for `operator-readout.sh:1502-1508` and `commands/wrap.md`.

---

## 8. Residual uncertainties (named, not hidden)

- **Why some panes' titles freeze mid-spinner** is confirmed for the `set-window-title` class
  (kitty's documented behaviour) but **not** confirmed for panes 312/316, whose titles are
  CC-generated summaries. I could not attribute those without mutating a live pane. Treat *any*
  single-sample spinner as unknown.
- **iTerm2**: every pane on this box today is kitty (`~/.claude/bin/it2` is a kitty shim). Whether
  the same glyph contract holds under real iTerm2 is **unmeasured**.
- **`sb_busy_jobs` in a shared checkout** over-attributes siblings' processes (measured, §6). The
  repo's own comment calls this the deliberate polarity (over-count rather than miss), but it means
  `BUSY … src=job` is not per-session evidence.
- **`cc-classify --all` cost**: MEASURED ~30 s for 17 sessions (it forks `jq` per transcript). Not
  suitable for a polling loop; `session_busy_live` is O(1) per session and is the right primitive.
