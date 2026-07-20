---
name: handoff
description: Prepare a stateless /clear continuation bridge — capture current LIVE state, write a disposable pointer to /tmp, open it in Cursor, and emit the paste line. By DEFAULT also fires the continuation autonomously when nothing is left open — new iTerm2 split pane, right account launcher (claude-nextN / claude-fableN), right model+effort, prompt auto-submitted; holds fire (paste-only) when open questions/decisions remain or on "paste only"/"hold fire".
allowed-tools: Bash, Read, Write, Grep, Glob
argument-hint: "[plan path or topic — optional] [paste-only|hold-fire to suppress the default fire; account/model/effort/surface prefs in plain words]"
---

# /handoff — stateless session continuation bridge

Prepare a disposable hand-off so the user can `/clear` and resume in a fresh context with **zero
state loss**. The DURABLE state lives in the repo plan; this emits only a stateless POINTER to it.

> **Typed/verbal parity (2026-07-13):** a typed `/handoff` injects this whole spec; a VERBAL or
> relayed handoff/succession intent ("hand off", "relieve", "you may self-close", "recycle the
> session") MUST be executed the same way — invoke this skill via the Skill tool and run its
> scripts; never improvise the fire/close chain from memory (the `handoff-intent-nudge.sh`
> UserPromptSubmit hook injects this reminder whenever such phrases appear). All three 2026-07-13
> "the handoff closed our session without opening the new one" reports arrived via verbal intent:
> two were a since-fixed watcher bug (nohup → setsid, `dd40eca`), the third a PERFECT succession
> rendered invisible by an undeclared, unfocused, unannounced close (§ Autonomous fire item 7's
> succession statement now makes that state unrepresentable).

**Core rule (`feedback-session-handoff-via-plan-not-prompt-files`):** a stateless bridge →
**`/tmp` or inline chat, NEVER committed** to the repo. It's regenerable from the durable plan,
so losing it (reboot / `/tmp` prune) costs nothing, and committing it just adds stale clutter.
`/tmp` is banned ONLY for *stateful* handoffs (where the file holds the only copy of real state).

## Target mode — set self-containment + isolation by the receiver (decide FIRST)

| Mode | Receiver / timing | Paste | Ref it points at |
|---|---|---|---|
| **A · same-session `/clear`** (default) | THIS session cleared + resumed; env/branch *usually* persist | POINTER + **self-locate header** | the live branch (you resume on it) |
| **B · cold NEW session, this one ENDS**, zero pre-work | one brand-new session pastes + runs it | self-EXECUTING bootstrap → pointer | the work's branch, by stable NAME |
| **C · FORK while this session KEEPS WORKING** / several handoffs at once | ≥1 concurrent session, each its own worktree | self-EXECUTING bootstrap → pointer | a DEDICATED FROZEN `handoff/<slug>` ref |

B and C still POINT for content (never duplicate the plan body — the staleness trap the Core rule
bans); they only add the BOOTSTRAP a cold session can't infer.

## Self-locate header (EVERY bridge, including Mode A)

Mode A's "env persists" holds only if the resume happens in THIS session's cwd — but a user who
*means* to `/clear` may instead open a NEW session that defaults to a **different worktree**. So
the paste ALWAYS opens with a one-line locator: a no-op when you're already home, a precise jump
when you're not — never a full-repo scan to "find ourselves again".

> `[locate] If not already here: cd <worktree-abs-path> (same machine). Else, in your clone: git checkout <branch>. Expected HEAD ~<short-sha> (informational only).`

- **`cd <worktree-abs-path>` is the PRIMARY locator, NOT `git checkout <branch>`.** Linked worktrees
  forbid the same branch in two worktrees, so a checkout run from a *different* worktree of this repo
  FAILS (`fatal: '<branch>' is already checked out at …`). The absolute path lands directly in the
  worktree that owns the branch. `git checkout <branch>` is ONLY the cross-clone / other-machine
  fallback (where that path doesn't exist).
- **Commit is a sanity-check, never a checkout target** — this repo land-rebases (SHAs move). Confirm
  `git log --oneline -1` ~matches the plan's latest entry; the worktree path + branch are authoritative.
- B/C don't need a separate locator line — their Step-0 bootstrap (`git fetch && checkout <ref>` in a
  fresh worktree) IS a stronger self-locate. The header is the Mode-A safety net that closes the
  "meant-A-but-got-a-new-session" gap.

**Cold-start guarantee (B & C)** — a zero-context session, given ONLY the paste, reaches every
referenced doc + a green baseline with no manual steps and no knowledge from this session:

1. **Reach.** Step 0 of the paste carries the git bootstrap (`git fetch && git checkout -b <slug>
   <ref> && git rebase origin/main`) — by stable NAME, never a rebase-mobile SHA. Verify the ref
   holds every referenced doc. If the target does NOT share this repo's `.git` (other machine/clone),
   PUSH the ref first — a non-`main` branch push does NOT trigger deploy.
2. **Env.** The referenced plan carries its OWN "Step 0 — setup" (install / env / DB + baseline-green
   gate); the paste points at it. If the plan has none, ADD it before emitting.
3. **Constraints.** Duplicate the 3-6 HARD constraints (don't-push, report-only, carve-outs) verbatim
   in the paste — the one deliberate duplication, so they bind even if the plan is skimmed.

**Mode C — freeze + uniquely name** (so ongoing main-session commits can't leak into the fork, and N
handoffs don't collide):

- **Freeze at emit:** `git branch handoff/<slug> <commit>` at the exact commit holding the plan + any
  prerequisite commits. Point the paste at `handoff/<slug>`, NEVER your live working branch — it keeps
  moving as you work and would drag unrelated in-progress commits into the fork. Frozen = stable + inert.
- **Unique `<slug>` per handoff** (topic, not "the plan"): bridge `/tmp/<slug>-resume.md`, branch
  `handoff/<slug>`, worktree `/tmp/wt-<slug>`. Forks coexist without clobbering.
- The fork runs in its OWN worktree (`git worktree add -b <slug> /tmp/wt-<slug> handoff/<slug>`); this
  session stays on its branch (CLAUDE.md concurrent-session isolation). Reuse the same source commit
  for several forks — each gets its own `handoff/<slug>`.

## Paste block — make the copy boundary VISIBLE

The Claude Code TUI renders everything monospace and gives a fenced code block **no visible box** — so a
bare fence is an INVISIBLE boundary there (confirmed 2026-06-18, two failed attempts: the user could not
see where the paste started or ended). The boundary the user can actually SEE is **two labeled rule lines**
drawn with box-drawing `─` (U+2500). Bracket the paste payload with them, in the `/tmp` file AND the inline
reply. Everything between the rules is the prompt to paste; the Mode framing and the "what's captured
durably / regenerable" notes stay OUTSIDE the rules.

Emit it EXACTLY like this — rule, fence, payload, fence, rule, with NO blank lines anywhere in the block:

──────────────── copy from here ────────────────
```text
<self-locate header>

<continue / bootstrap  →  status  →  next>
```
───────────────── to here ──────────────────────

The fence stays even though it is invisible in the TUI because it (a) preserves the payload's own line
breaks and (b) is a markdown block boundary, so the rule above it does NOT soft-wrap-join the first
payload line — and in Cursor / any rich renderer the `/tmp` file additionally gets a real code box. The
two `─` rules are the canonical VISIBLE boundary; the fence is the invisible mechanism under them.

- **No blank line anywhere between the two rules.** Top rule directly above the fence; first line in the
  fence = the self-locate header; last line in the fence = the final payload line; bottom rule directly
  below the closing fence. A leading/trailing blank gets copied too — that padding is exactly what worsens
  the copy block. (Blank lines BETWEEN payload sections, inside the fence, are fine — meaningful separators.)
- **Only the payload sits between the rules.** For-the-user prose goes above the top rule or below the
  bottom rule, never between them.
- **Don't indent** the rules or the payload (indentation becomes copied leading whitespace).
- **Rules are box-drawing `─` (U+2500), never markdown `---`** — a `---` directly under a text line renders
  as a setext heading, not a rule.

## Steps

1. **Identify the active plan.** If `$ARGUMENTS` names a plan/path/topic, use it. Otherwise pick
   the most-recently-modified plan doc (`ls -t docs/plans/*.md .claude/plans/*.md 2>/dev/null | head`)
   or the plan this conversation has been working in. **If there's no durable plan yet, STOP and
   update/create one first** (durable scaffolding + a status-log line) — the bridge is worthless
   without durable state to point at.

2. **Capture CURRENT live state** (read live — never cache stale values):
   - `git rev-parse --short HEAD`, branch, and the **absolute** worktree path
     (`git rev-parse --show-toplevel`) — the self-locate header needs the abs path, not a relative cwd.
   - One live status line if relevant (typecheck / lint / build / deploy, or the plan's latest
     status-log entry).
   - The single concrete NEXT step you and the user were about to take.
   - **Freeze the mission/DoD for the successor (T-P4-4):** run
     `~/.claude/hooks/dod-persist.sh set "<the current \`Scope (frozen): …\` line>"` so the durable
     worktree-keyed DoD file is fresh. A `--recycle` is an exit+relaunch, NOT a PreCompact, so the
     successor's SessionStart re-injection carries nothing unless this capture runs. If no
     `Scope (frozen):` line was stated this session, derive it from the plan / `/goal` and set it.

3. **Write the bridge to `/tmp/<slug>-resume.md`** (UNIQUE `<slug>` per handoff — topic, not "the
   plan" — so several never clobber; ≤ ~30 lines, a POINTER not a copy):
   - Header: "STATELESS · disposable · regenerable from the plan — that's why it's /tmp, not committed."
   - A **"Paste into the new session"** block — bracketed by two labeled `─` **rule lines** (§ Paste block),
     so the copy boundary is VISIBLE in the TUI — that ALWAYS opens with the **self-locate header**
     (§ Self-locate — abs worktree path primary, branch fallback, commit informational). Mode A then
     adds: *"Continue the <plan> session. Read `<plan-path>` § <resume/status> first. Status:
     <TL;DR + live HEAD>. Next: <step>."* Mode B/C: the Step-0 bootstrap (reach `<ref>` +
     baseline-green per § Target mode) IS the self-locate, THEN the read-the-plan pointer + the
     duplicated hard constraints.
   - 4–8 **facts for the fresh context**: worktree/branch/HEAD; landmines (pinned tool versions,
     concurrent-session hazards, known false-positive signals); any open thread.
   - A pointer to the durable plan's resume section (§ Resumption / Phase N / RESUME STATE /
     status log — whatever the plan uses). Do NOT duplicate the plan's content.

4. **Surface the artifacts — Cursor ONLY on a held fire:** when the fire is HELD ("paste only" /
   "hold fire" / the readiness gate holds — i.e., the human will actually copy-paste), open the
   bridge: `cursor /tmp/<slug>-resume.md` (print the path if the `cursor` CLI is absent). On an
   **autonomous fire (the DEFAULT), NEVER open Cursor** — that step existed only for the manual
   copy-paste era. Instead emit every artifact path (the bridge and each `/tmp/fire-<slug>.txt`) as
   a **bare absolute path on its own line** in chat — the clickable form (the CC TUI linkifies bare
   file paths, and iTerm2 semantic history Cmd+click works on them regardless; verified 2026-07-11).
   Do NOT wrap paths in markdown `[label](file://…)` links — no clickability gain, and the label
   hides the path.

5. **Emit the paste payload inline** in your reply — bracketed by the same two labeled `─` rule lines
   (§ Paste block) — so the user can copy it straight from chat without opening the file, with the copy
   boundary visible and no leading/trailing padding between the rules.

6. **Fire it (DEFAULT when nothing is open — § Autonomous fire):** after emitting the paste, run the
   readiness gate — it is the § Post-fire disposition taxonomy read PRE-fire: any live R-USER (open
   discussion, unanswered question), R-DECIDE (a decision the user must make before the new session
   starts — STOP-ASK surfaces, unfrozen scope), or R-WORK blocker (a doc the payload references that
   doesn't exist yet)? If NONE → fire autonomously: write each track's payload to `/tmp/fire-<slug>.txt` and
   spawn via `~/.claude/scripts/handoff-fire.sh` — every track, not just the first. A SINGLE Mode-A
   track fires as `--recycle` (this pane exits + relaunches with the payload — § Autonomous fire item 4); multi-track,
   forks, and account switches spawn panes. If ANY open item → name them, HOLD fire, and fire once
   resolved. "paste only" / "hold fire" / "no fire" always suppresses; an explicit "fire" overrides a
   hold. The inline paste (step 5) is always emitted as the manual fallback.

7. **Disposition (EVERY fire, then EVERY turn until close — § Post-fire disposition):** after the
   per-track fire report, run `~/.claude/scripts/handoff-disposition.sh` (un-fakeable mechanical
   reads), add the R-USER/R-DECIDE judgment only you can make, and END THE TURN with exactly ONE
   disposition line: `🔚 DISPOSITION: CLOSE …` → self-close as the turn's last action (§ Autonomous
   fire item 7), or `⏳ DISPOSITION: OPEN — <R-CODE>: …` drawn from the CLOSED taxonomy. Re-evaluate
   and re-emit at the end of every subsequent turn until the session closes. A post-fire session is
   NEVER silently open: no disposition line = a contract violation, not a default-open.

## Autonomous fire — end-to-end launch (DEFAULT when nothing is open; "hold fire"/"paste only" suppresses)

Completes the flow the paste block leaves manual: opens a fresh **iTerm2 surface**, `cd`s to the right
place, and types `<launcher> "$(cat /tmp/fire-<slug>.txt)"` into it — the prompt auto-submits as the
session's first message. Mechanism = `~/.claude/scripts/handoff-fire.sh` (generalizes the proven
2026-07-02 `/tmp/fire.sh` playbook; see memory `reference-parallel-session-launch-playbook`). The
launchers are per-account zsh functions/aliases, which is WHY the script types into an interactive
pane via osascript `write text` instead of exec'ing them.

**1 · Payload → prompt file.** The paste-block payload (same Mode A/B/C content rules) goes VERBATIM
into `/tmp/fire-<slug>.txt`. Safe for any content: `"$(cat file)"` output is never re-expanded by the
shell (verified) — metacharacters and newlines arrive literally; only trailing newlines strip.

- **Dynamic Workflows / ultracode:** prepend the word `ultracode` to the payload's first line when the
  receiving session should use multi-agent Workflow orchestration. Prompt-level keyword only — no CLI flag.
- **`/goal` (or any SKILL-BACKED slash command — never built-ins like `/clear`/`/model`, which only
  the TUI parses):** recognition is POSITIONAL — it must be the payload's very FIRST line
  (`/goal <one-line goal>`, pointer/constraint lines after). A `/x` buried mid-payload reads as
  ordinary prose and is NOT invoked (useful when you want to *mention* a command without running it).
  The CLI does not parse slash commands out of the initial prompt — the receiving model dispatches a
  LEADING user-typed `/x` via its Skill tool (current harness behavior, system-prompt-driven;
  re-verify on CC bumps), equivalent in effect for command-file skills. When `/goal` leads a fired
  payload, put the `[locate]` self-locate line immediately AFTER it — in fire mode the spawner's `cd`
  already does the locating, and the header stays intact for the manual-paste fallback.
  > **🚨 4000-CHARACTER GOAL CAP — a `/goal` payload consumes the ENTIRE payload (every line, not just
  > the first) as the goal condition, and the goal condition is hard-capped at 4000 chars.** A longer
  > payload is REJECTED at the fired session ("Goal condition is limited to 4000 characters (got N)")
  > and the session gets NO task — a silent dead fire (observed 2026-07-10: a 4901-char inlined brief
  > was rejected). **Fix — keep the goal SHORT by REFERENCING a durable doc, never inlining the brief:**
  > `/goal <one-line objective> — full brief at <path>` where `<path>` is a committed plan/research doc
  > (`docs/plans/*.md`) or a `/tmp/<slug>-brief.md` the fired session reads (same machine ⇒ `/tmp` is
  > reachable; a committed doc is more durable). The detail lives in the doc; the goal just names the
  > objective + the pointer + the 3-6 HARD constraints — keep the whole payload well under 4000. If a
  > brief genuinely can't be shortened AND you don't need the persistent Stop-hook goal, **OMIT `/goal`
  > and send the brief as a plain prompt** (no char cap — but no goal-condition). Budget the payload:
  > if `wc -c` on the fire file is near 4000, move detail into the referenced doc BEFORE firing.
- Omit both for a plain continuation prompt.

**2 · Account → launcher.** Explicit user choice wins. Else `--account auto` ranks by **live
limits**: `claude-accounts --rank general|fable` (fable when `--model fable`) — real 5h/weekly/
Fable headroom, reset urgency, and live session spread from the oauth usage endpoint, shared-cached
90s so waves don't stampede it (SSOT: `~/.claude/accounts.json`; dashboard: `/accounts`). If the
rank says NO account is routable (policy: exhausted/cutoff/window), the fire HALTS — never fire
blind. Only when live limits are UNREADABLE (tool/endpoint down) does it degrade to the trailing-5h
transcript-activity proxy. Static hint orders are retired — two of them contradicted each other
within 48h. If a fired session rate-limits, relaunch the SAME worktree on another `claude-nextN`
(no rework). Account = launcher suffix only; the worktree is account-agnostic.

**2a · Pre-fire account sweep — never hand off blind to a stranded account.** BEFORE it ranks,
`handoff-fire.sh` runs `claude-accounts --fresh` (which auto-heals STALE accounts in-process and
rewrites the shared cache the `--rank` above then reads) and inspects every account's auth. For each
account whose auth is broken it acts by PROVABLE recoverability, never by guesswork:

- **`token-invalid` with a live refresh token + ZERO live sessions →** it runs **account-relogin
  Phase 1 headlessly** — the same rotation-safe `claude auth login` refresh grant that
  `claude-accounts` heal() does, under the SAME `/tmp/claude-accounts-heal-<acct>.lock` (never two
  logins on one account; deferred if a heal is already in flight). The account is healed in place and
  routable next sweep. It NEVER relogins under a live CC (`k>0`) — that session owns the token lifecycle.
- **`logged-out` / `keychain-error` / a revoked refresh token →** not headless-recoverable, so it
  embeds ONE **`## ACCOUNT STATE`** bridge line into the fired brief — `<acct> <state> · last-known
  weekly ~<N>% @ <HH:MM> · fix: claude-accounts --relogin-info <acct> → account-relogin skill (Phase 2, browser)`
  — so the successor can re-auth it or deliberately route around it instead of silently over-loading
  the survivors. (Last-known quota comes from the durable last-good ledger — Part A1, landed: the sweep
  reads the `stale_quota` / `weekly_pct` / `quota_as_of` fields `claude-accounts --fresh --json` stamps
  from its TTL-free `~/.claude/logs/claude-accounts-lastgood.json`, so it survives a `/tmp`-sweep and no
  longer decays after one sweep. The `@ <HH:MM>` recency stamp mirrors the dashboard table.)

The sweep is **best-effort and never blocks a fire** (any tool/parse failure ⇒ it's skipped, the fire
proceeds). It is **wave-throttled** (`HANDOFF_ACCOUNT_SWEEP_THROTTLE_S`, default 60s — the first fire
of a wave sweeps, the rest reuse its result so a burst doesn't stampede the endpoint) and disableable
with `HANDOFF_ACCOUNT_SWEEP=off`. Run it standalone any time with `handoff-fire.sh account-sweep`
(prints the bridge section; empty when all four accounts are routable). Design:
`docs/research/desk-anti-hitl-2026-07-19.md` Part A; skill: `account-relogin`.

**3 · Model + effort.** Pick per the SSOT ladders (`~/.claude/model-config.yaml` `effort_defaults` +
`roles`) — Opus and Fable run DIFFERENT ladders; never carry one model's effort habit onto the other:

| Receiver's work | Fire flags | Session runs |
|---|---|---|
| Implementation / research / synthesis lead (THE DEFAULT) | *(none)* | Opus 4.8 @ **max** (`effort_defaults.default` — certified: xhigh regresses on grounding-heavy work) |
| ultracode / Dynamic Workflows lead | *(none)* + `ultracode` keyword in the payload | same Opus 4.8 @ max — the keyword changes ORCHESTRATION, not effort; workflow slots pin their own per-agent model/effort (`workflow_judge`, `workflow_synthesis_worker`) |
| Bounded verify / judge-only session | `--effort xhigh` | Opus @ xhigh (`verify_judge` — ties max at lower cost ONLY for bounded-grounding work) |
| Fable frontier (derivation panels, judgment) | `--model fable --probe` | Fable 5 @ **high** (`fable_default` — NOT max: Fable@high ≈ Opus@max; max over-deliberates + burns the window) |
| Fable capability-sensitive (security/arch judgment) | `--model fable --effort xhigh --probe` | Fable 5 @ xhigh (`fable_capability_sensitive`) |
| Fable routine | `--model fable --effort medium --probe` | Fable 5 @ medium (`fable_routine`) |

Mechanics: `--effort`/`--model` are appended AFTER the launcher-injected defaults (last-wins, verified),
so overrides always stick. The script WARNS (does not block) when `frontier_access.active` != true — the
hard gate is the API rejection — hence ALWAYS pair Fable with `--probe` (rejection signature: ~600ms,
"model may not exist or you may not have access" → script walks to the next account or fails loud).

**4 · Location.** Existing worktree → `--cwd <abs-path>`. Fresh track → `--worktree <slug>` — fast path
CLAIMS a warm pool slot when `<repo>/scripts/worktree-pool.sh` exists and base is origin/main (~3s,
fully provisioned, no in-pane install; slot-locked, race-free); cold fallback does the racy
`git worktree add` serially + copies `.env.local` with the ~16-19s `pnpm install` running IN the new
pane so parallel fires overlap. Read-only in the repo root → `--cwd <repo> --in-place`
(`CLAUDE_ISOLATION_SKIP=1`). Nothing given → repo root + launcher self-routing (`_cc_route_check`
auto-creates a `cc-<ts>` worktree). **Mode C/B fork:** `--worktree <slug> --base handoff/<slug>` (the
spawner creates the branch AT the frozen ref) and DROP the payload's Step-0 `git checkout -b` line —
the branch already exists; keep only the rebase/verify lines. `--wtroot` relocates the worktree parent
if the bridge promised `/tmp/wt-<slug>`. **Mode A fire (single track) → RECYCLE this pane, not a new
pane:** `--recycle` = **EXIT + RELAUNCH**, never `/clear`+queued-payload (rebuilt 2026-07-03 after the
catnav incident). CC's queue is TYPE-ASYMMETRIC: plain text typed mid-turn is STEERED into the
still-running turn at the next tool-result boundary (arrives as a `queued_command` attachment) — and the
fire script's own Bash call guarantees that boundary — while `/clear` holds until turn end. So the old
design deterministically ran the payload INLINE in the old context with `/clear` armed behind it to wipe
everything. (The Jul-2 probe that "verified" queue ordering used a pure text-generation busy turn — no
tool boundary, so nothing steered.) The rebuilt flow: arm a detached watcher → type `/exit` — a THIRD
semantics: it INTERRUPTS any in-flight turn and exits in seconds (E2E'd) → the watcher ps-polls the tty
until claude is gone, then types `cd <cwd> && CLAUDE_ISOLATION_SKIP=1 <launcher> [flags] "$(cat
/tmp/fire-<slug>.txt)"` into the plain shell via the it2 python-API CLI (AppleEvent-free,
detached-proven; Enter = `\r`, Ink ignores `\n`). ⚠ Hardened 2026-07-13 after 2 same-day stranded
panes: "detached" MUST mean **setsid** (`detach()` in the script — own session+pgid, PPID 1), because
the `/exit` interrupt SIGKILLs the in-flight Bash tool's whole process GROUP and a nohup'd watcher dies
with it (0-byte log, no relaunch — the Jul-12 successes had only won the return-before-interrupt race).
The script now also gates `/exit` on the watcher's armed-heartbeat line (no heartbeat → abort, session
stays alive) and post-confirms a claude process on the tty after relaunch (guarded retype once, then a
pane-visible `# HANDOFF RELAUNCH FAILED — run manually: …` comment). Consequences: the fire call is the
turn's LAST action — emit the report + manual-fallback line BEFORE it (the interrupt can kill the Bash
tool's own output); the payload travels VERBATIM (multi-line fine — no flatten); model/effort ride as
launcher FLAGS (typed `/model`/`/effort` mutated the account's saved defaults — gone); account defaults
to THIS session's (CLAUDE_CONFIG_DIR-derived), `--account`/`--launcher` override, so cross-account
recycle works; the old transcript stays resumable via `--resume`. E2E 3× on 2.1.183 incl. a mid-turn
fire; group-kill repro + fixed-chain E2E (fake pane, real script) on 2.1.207, 2026-07-13. Re-verify the
steering + `/exit`-interrupt semantics on CC version bumps.

**5 · Surface.** Default = `--split-right`: splits the CURRENT pane like ⌘D (same view, same profile) —
the new session appears right next to where the user is looking, exactly like an Agent Teams teammate
pane. `--split-down` (⌘⇧D) · `--tab` (background tab, NOT in the current view) · `--window`. All fall
back to a fresh window when none is open. Use `--dry-run` first when anything is unusual — it prints
the account ranking + the exact command it would type. Occasional flags: `--extra "--permission-mode
plan"`, `--launcher` for an explicit tier (e.g. `claude-fable-x`; note it skips the probe),
`--repo`/`--wtroot`/`--base` for non-default placement — full list in the script header.

> **`/handoff` fires pass `--follow` — you are watching.** `/handoff` is operator-initiated, so its
> fires SHOULD raise + land your view on the continuation (the ⌘D split-right experience). `--follow`
> is what turns the raise back on; **every `/handoff` fire below carries it.** WITHOUT `--follow` a
> fire is AUTONOMOUS and never moves your focus (C1, 2026-07-19, the ttys018 mis-inject): the default
> surface becomes a background tab, nothing is raised, and the operator-focused session is captured +
> asserted unchanged. That background mode is for the DESK's own automation (`cc-dispatch`, `/goal`,
> `waiting-recycle`, wave fires) — none of which read this file — so it fires alongside a typing
> operator without stealing focus. When YOU run `/handoff`, keep `--follow` on.

> **Split-right is the STICKY default — do NOT preemptively downgrade to `--tab`.** The window is
> comfortable at **3-4 side panes** (⌘D-style), so a 2nd or 3rd concurrent handoff still fires
> `--split-right`, NOT `--tab`. Reach for `--tab` ONLY when (a) the firing window already holds ~4+
> panes, or (b) the user explicitly asks for a tab/background. One split + one tab is WORSE — the
> "why did it open in a tab?" inconsistency (user-flagged 2026-07-10) — than a slightly busier pane
> row; visible side-by-side is the whole point. If you catch yourself picking `--tab` to "avoid
> crowding" at 2-3 panes, that IS the anti-pattern — choose `--split-right`. The model (surface is
> the agent's judgment call, not the user's) never inherits a prior fire's `--tab`.

```bash
# typical: fresh track, auto account, Opus@max, split pane in the current view (⌘D-style default).
# --follow = you're watching this /handoff → raise + land your view on it (drop it for a background fire).
~/.claude/scripts/handoff-fire.sh --prompt-file /tmp/fire-<slug>.txt --worktree <slug> --follow
# a 2nd/3rd concurrent handoff STILL splits (do NOT switch to --tab here) — ⌘D again, e.g. below:
~/.claude/scripts/handoff-fire.sh --prompt-file /tmp/fire-<slug>.txt --cwd <wt> --model fable --probe --split-down --follow
# --tab is for OVERFLOW ONLY (window already ~4+ panes) or an explicit user "put it in a tab" —
# a non-default surface, so record WHY with --surface-reason (silences the split-right advisory)
~/.claude/scripts/handoff-fire.sh --prompt-file /tmp/fire-<slug>.txt --worktree <slug> --tab --follow --surface-reason "overflow: window already ~4+ panes"
```

**6 · Waves — N parallel handoffs (THE high-value case).** A fire request covers EVERY track in the
handoff — never just the first, never crammed into one session. Each track gets its OWN fresh-context
session, prompt file, worktree, and account slot — the session-level analog of an Agent Teams wave,
and like a wave there is no track cap (practical ceiling ≈ 4 accounts × 2 concurrent = 8).

- One `/tmp/fire-<slug>.txt` + one script call per track, invoked back-to-back serially. Serial calls
  are NOT a bottleneck: each call only does the racy `git worktree add` (fast, race-safe when serial);
  the ~16-19s `pnpm install`s run INSIDE the panes and overlap — wall-clock ≈ one setup, not N.
- **Account spread is the lead's job, not `--account auto`'s:** auto ranks per call from a 90s
  shared cache and cannot see tracks that haven't STARTED yet, so a rapid wave on auto would pile
  every track onto the same top-ranked account. Rank once — `claude-accounts --rank general` (or
  any `--dry-run` prints it) — then assign explicitly round-robin down that ranking, ≤2 tracks per
  account. If a track rate-limits mid-flight, `/exit` and relaunch the SAME worktree on another
  account (no rework; the worktree is account-agnostic).
- **Surfaces at wave scale:** every surface (`--split-right`/`--split-down`/`--tab`) anchors to the
  pane you fired from (via `$ITERM_SESSION_ID`), so the whole wave lands in YOUR window. Consecutive
  `--split-right` calls build a teammate-grid there — comfortable to ~3-4 panes; beyond that give each
  overflow track `--tab` (background tabs in the same window). (The old "first `--window`, rest `--tab`"
  trick to park a wave elsewhere no longer holds — `--tab` follows the firing pane now, not the
  last-created window; give each track its own `--window` if you want them out of your working window.)
- Per-track model/effort still applies row-by-row from the §3 table — a wave can mix Opus tracks and
  a probed Fable track freely.

```bash
# 3-track wave: rank once, spread explicitly, splits for the first two, tab for the third.
# --follow on each: an operator-initiated wave lands its grid in your view (drop it for a background wave).
~/.claude/scripts/handoff-fire.sh --prompt-file /tmp/fire-sec.txt   --worktree wsfa-sec   --account next4 --follow
~/.claude/scripts/handoff-fire.sh --prompt-file /tmp/fire-money.txt --worktree wsfa-money --account next3 --follow
~/.claude/scripts/handoff-fire.sh --prompt-file /tmp/fire-fable.txt --worktree wsfa-fable --account next2 --model fable --probe --tab --follow --surface-reason "overflow: 3rd track"
```

**Fire guardrails:** the gate is READINESS, not an explicit ask — firing is the default close of
`/handoff` because the whole point is automating the manual open-new-session flow away. Fire when no
open discussion/question/decision remains; HOLD (paste-only) when any does — name what's open, resolve
it, then fire. "paste only" / "hold fire" / "no fire" always wins; an explicit "fire" overrides a hold.
One handoff = the WHOLE wave: N tracks → fire all N, never just the first. One script call per track,
invoked serially (keeps worktree adds race-safe). Report a per-track table (launcher@destination,
surface, prompt path, **notify-back?** — yes+UUID when `--notify-back` armed R-PING, else no) after
firing, followed by each track's bridge + fire-file paths as bare absolute paths on their own lines
(the clickable form — step 4), then emit the disposition (§ Post-fire disposition). All existing
bridge guardrails still apply to each payload.

**7 · Self-close — retire the emptied main session (the CLOSE arm of § Post-fire disposition).**
Invoked ONLY off a `🔚 DISPOSITION: CLOSE` emission — a pane-spawn wave is away and no taxonomy
reason holds (never bare judgment; the helper ran first). The main session then closes ITSELF:
`handoff-fire.sh self-close --successor <pane-uuid>` (or `--terminal` when truly nothing continues)
arms its detached watcher FIRST,
then types `/exit` into its own pane FOREGROUND (a typed `/exit` INTERRUPTS any in-flight turn and exits
in seconds — so everything that must survive precedes it); the watcher ps-polls the pane's tty until the claude process exits and closes
the pane via the `~/.claude/bin/it2` shim (window follows when it was the last pane). Graceful-first:
`/exit` runs SessionEnd hooks and leaves the transcript resumable (`--resume` / claude-search); the
watcher force-closes teammate-style only at its 180s ceiling (logged to
`/tmp/handoff-selfclose-<sid>-<ts>.log`). Empirical E2E: graceful close in 9s; the full succession
chain (verify → announce → close → focus) E2E'd 9/9 on 2026-07-13 (`scripts/handoff-selfclose-e2e.sh`).

> **🚨 SUCCESSION STATEMENT — mandatory (2026-07-13, the third "where did my session go" incident).**
> A pane close is operator-visible surface: a close with no declared continuation reads as "the
> handoff killed our session" even when the succession actually SUCCEEDED (the 23:03 incident — the
> successor was alive one pane over; the announce died with the closing pane and nothing moved the
> operator's focus). Bare `self-close` now exits 2. Declare succession explicitly:
> - `--successor <pane-uuid>` — the live continuation's pane. The script (1) VERIFIES it alive
>   (pane resolvable + claude on its tty) BEFORE typing `/exit` — abort 3 otherwise; (2) ANNOUNCES
>   the succession INTO the successor via `cc-notify` (visible line in the SURVIVING transcript +
>   mailbox record — the report emitted in the dying pane dies with the pane); (3) FOCUSES the
>   successor after the close so the operator's view lands on the continuation, never a void.
> - `--terminal` — end-of-line: nothing continues this session's work. Say so explicitly.
> - Dirty tree on a SHARED checkout: when the dirt is the successor's own in-flight work (the
>   23:02 case — the coordinator's cwd showed the exit-lead's uncommitted severance), pass
>   `--dirty-owner successor` (requires a verified-alive `--successor`; the close loses nothing
>   because the owner survives). `--allow-dirty` remains the blunt, potentially-lossy override.
> - **Remote relief** (retiring ANOTHER session's pane): prefer `cc-notify` instructing THAT
>   session to run its own `self-close --successor …` (its SessionEnd hooks + disposition stay
>   honest). Direct `self-close --session-id <their-pane>` is the fallback for an unresponsive
>   session and carries the SAME succession-statement obligation. Never raw `it2 session close` /
>   hand-typed `/exit` for teardown — those leave no announce, no focus, no log.

Hard-won constraints
baked into the script: ALL keystrokes are typed foreground — detached osascript AppleEvents to iTerm2
fail silently (3/3 observed); the watcher does only AppleEvent-free work (ps + the shim's python
websocket API, both proven detached — `session focus` rides the same proven transport). Guards: no
succession statement exits 2; dead/missing successor aborts 3; dirty git tree refuses (see above);
a pane with no CC on its tty skips `/exit` and just closes (mis-arm/launch-latency protection); emit
the final report BEFORE arming — it stays on screen until the close (and the successor's transcript
carries the announce after it). NEVER pair with `--recycle`.

**Prior art (why this shape):** it is the session-level analog of Agent Teams' teammate lifecycle — CC
spawns each teammate pane via `it2 session split -s <lead>` (the `~/.claude/bin/it2` shim injects the
`Claude-Teammate` profile), records the pane's session UUID at `teams/<team>/config.json →
members[].tmuxPaneId`, and closes it via `it2 session close -f -s <id>` (shim-rerouted to python
`async_close(force=True)`), with idle-close owned by the TeammateIdle hook (`teammate-auto-shutdown.sh`,
checkpoint-first). The fire flow differs deliberately: its sessions are PEERS on their own accounts —
opened with the human-facing default profile so the zsh launchers resolve, and retired by the session
ITSELF via § item 7's graceful self-close once its work is fully handed off (or by the human), never by
an idle hook.

**8 · Two-way — back-channel ping (`--notify-back`, opt-in).** Fire is one-way by default (fire-and-forget:
the fired peer is an independent OS process, usually on another account, with no return address). Add
`--notify-back [UUID]` to close the loop: it appends a back-channel trailer to a COPY of the prompt (NEVER
the caller's file) telling the fired session to ping the ORIGINATOR on completion / decision gate / blocker
via `cc-notify <UUID> "HANDOFF-PING <slug>: <status>"`. UUID defaults to THIS firing pane
(`$ITERM_SESSION_ID`, or `--session-id`). The ping rides the v2 INBOX transport — it lands in the
originator's mailbox and is surfaced as context at its next safe boundary (or its `cc-await-ping` watcher
wakes it), NEVER as keystrokes into a live composer (research: `docs/research/HANDOFF_BACKCHANNEL_2026-07-10.md`;
plan + v2 anti-keystroke redesign: `docs/plans/TWO_WAY_SESSION_COMMS_PLAN.md`).

**`--notify-back` ARMS R-PING** (§ Post-fire disposition): from the moment such a track fires, every
disposition emission MUST carry an `R-PING: awaiting <before|during|after> ping from <slug>` clause
until the ping lands — and the firing session pairs it with a background `cc-await-ping <own-uuid>`
so the discharge is event-driven (its `--timeout` is the fallback wake), never a poll-and-hope.
Pass the UUID EXPLICITLY even though it defaults: the disposition helper attributes the watcher to
this session by matching the uuid on the process cmdline — a bare watcher is invisible to it. The
three companion CLIs (in `~/.claude/bin/`, on PATH):

- **`cc-notify <name|uuid|--self> "<msg>"`** — the general any-session→any-session primitive, and the ONLY
  sanctioned send path. **v2 (2026-07-20 — the anti-keystroke redesign):** it ENQUEUES the message to the
  target's inbox `~/.claude/mailbox/<uuid>.md`; it does NOT keystroke the composer. The v1 it2 `session
  send` transport is GONE — it raced the user's live input (at a bash prompt the surface text ran as a
  command, `(eval):1: parse error`; at a Claude prompt it corrupted the half-typed message + cursor). The
  target's `hooks/mailbox-drain.sh` surfaces the mail as CONTEXT (additionalContext on
  SessionStart/UserPromptSubmit, or folded into `session-continue`'s Stop reason for a looping session),
  and its armed `cc-await-ping` watcher wakes it within a poll — so the message ALWAYS lands as something
  it READS, at a safe boundary, NEVER as keystrokes on the live input line (regular box OR bash box).
  Resolves a friendly name (registry / `cc-sessions`) or a raw pane UUID. Exit: **0** = enqueued (stderr
  says "wake-path armed" for a watched live target, "NO watcher armed" for a live-but-idle one, "mailbox
  only" for a not-live/closed pane); **3** = unresolvable; **5** = inbox UNWRITABLE (self-escalates — a
  durable alarm record + a best-effort phone page, since a message that cannot persist must be loud). The
  `<uuid>.seen`/`.acked` split cursor makes delivery exactly-once + lets the guard see a loss. `--mailbox-only`
  records without the liveness verdict; `--from <name>` attributes. The fail-loud backstop **`cc-inbox-guard`**
  (rides the reaper cadence) escalates any message enqueued to a live session but never CONSUMED — nothing
  silently vanishes.
- **`cc-await-ping [<uuid>]`** — the modal-safe PULL complement AND the idle-WAKE. Launch via
  `Bash(run_in_background)` when going idle (after a `--notify-back` fire, or as a monitoring desk's standing
  listener); it polls the shared `.seen` cursor — firing IMMEDIATELY on mail already pending at arm time
  (v2 F6a; the old `wc -l` baseline missed exactly that line) — and on a new line prints it (advancing the
  cursor) then exits, so the harness's task-completion notification re-invokes you with the mail in the
  notification body. It beats a `<uuid>.watching` heartbeat each poll so `cc-notify`/`cc-announce` can
  confirm a real WAKE path (not mere liveness). Bounded `--timeout` (default 1800s).
- **`cc-sessions [--json|--names]`** — lists live sessions (name→pane UUID) for addressing; sweeps stale
  entries (pane gone or owning process dead). Sessions register on `SessionStart` (predating sessions
  register on next restart); the registry is account-agnostic (`~/.claude/cc-registry/`), so cross-account
  pings resolve.

## Post-fire disposition — close, or explicitly open (Step 7's contract)

A fire delegates the WORK; it does not settle the fate of the session that fired. This contract does.
**After EVERY fire (any mode, every track), and at the end of EVERY subsequent turn until the session
closes, end the turn with exactly ONE of:**

- `🔚 DISPOSITION: CLOSE — nothing remains in this session.`
  → then `~/.claude/scripts/handoff-fire.sh self-close --successor <pane-uuid>|--terminal` AS THE
  TURN'S LAST ACTION (§ Autonomous fire item 7; its dirty-tree guard still applies, and the
  succession statement is MANDATORY — bare self-close exits 2). Sole exception: after a `--recycle`
  fire the recycle itself IS the close — the CLOSE line goes in the pre-fire report and self-close
  is NEVER called (the pane is the continuation).
- `⏳ DISPOSITION: OPEN — <R-CODE>: <specific instance> → closes when <discharge condition> → then <single next action>.`
  One clause per LIVE reason; several live reasons = several clauses in the same emission,
  worst-first: **R-DECIDE ≻ R-USER ≻ R-PING ≻ R-WORK ≻ R-DIRTY** (user-blocking first, then
  event-driven waits, then own work, then hygiene).

The format is itself the test: a reader must be able to answer *"why is this session open, what ends
that, and what happens then?"* from the emission ALONE. An OPEN line missing any of its four parts —
code, specific instance, discharge condition, next action — violates the contract; so does a
post-fire turn that ends with neither line. A post-fire session is never silently open.

**Run the helper first — mechanical reasons are read, never self-reported.** Before every emission:

```bash
~/.claude/scripts/handoff-disposition.sh [--session <uuid>] [--tasklist <id>] <fired-slug…>
# stdout: {"dirty":…,"mailbox_pending":[…],"await_ping_running":…,"fired_peers_alive":[…],"open_tasks":…}
```

Exit 1 = mechanical reasons exist → the matching clauses (R-DIRTY / R-PING / R-WORK) are MANDATORY
in the OPEN emission. Exit 0 = close-eligible pending the two judgment reasons only the model can
read from the conversation: R-USER and R-DECIDE. The model judges those two; the script settles the
rest. A pending mailbox line means an unprocessed ping: process it, `--ack`, re-run, then emit.

### Closed reason taxonomy — the ONLY reasons a session may stay open

| Code | Holds the session open when | Discharges when | Then |
|---|---|---|---|
| **R-PING** | awaiting a back-channel from fired session(s) `<slug…>` — *before* (about to fire more tracks), *during* (decision-gate / blocker pings), or *after* (completion ping) the peer's run. Armed by `--notify-back` (§ item 8); pair with a background `cc-await-ping` so discharge is event-driven, its `--timeout` the fallback wake | the ping lands — or the timeout fires: check fired-pane liveness via `cc-sessions`; a DEAD peer escalates to R-DECIDE (the user rules on the lost track) | process the ping → re-emit disposition |
| **R-USER** | the user is mid-conversation / a reply is plausibly incoming — their LAST message is unanswered, or they said "stay open" | their message is handled and no new reason opened; or they say "close it" / go idle after an offered close | re-emit |
| **R-DECIDE** | a NAMED open decision / STOP-ASK only the user can rule on | the user rules | act on the ruling → re-emit |
| **R-WORK** | NAMED current or follow-on work THIS session owns (not delegated to a fired track) | the work is done, verified, committed | re-emit |
| **R-DIRTY** | uncommitted in-scope changes in this worktree (self-close would refuse anyway) | a task-clean commit | re-emit |

No other reason exists. "Just in case", "might be useful", "the user may want something" — BANNED:
if no row fits, the session closes. Every discharge ends in *re-emit* — the contract is a loop whose
only exit is CLOSE. The taxonomy is CLOSED: a candidate 6th reason is a PROPOSAL in the plan's status
log (`docs/plans/HANDOFF_DISPOSITION_PLAN.md`), never a silent addition here. This table is also the
readiness gate of step 6, read pre-fire — one table, two read points, so gate and taxonomy cannot drift.

Worked example (two live reasons, worst-first):

> `⏳ DISPOSITION: OPEN — R-USER: your question on E2E scope is unanswered → closes when answered with nothing new opened → then re-emit. · R-PING: awaiting completion ping from ship-hardening (cc-await-ping running, 1800s fallback) → closes when the ping lands → then process it + re-emit.`

**Kill-switches (the user's words override everything above):**

- "close now" → CLOSE this turn: commit first if R-DIRTY; `--allow-dirty` only on explicit user say-so.
- "stay open" → a standing `R-USER: user said "stay open" → closes when they release it → then re-emit`
  clause until they release it.

**No Stop hook enforces this** — same rationale as the Session Close Protocol: an advisory hook is
inert, a blocking hook is an infinite-loop anti-pattern. The contract is command discipline (this
section) plus the deterministic helper; the un-fakeable part lives in the script.

## Guardrails

- **The pre-fire account sweep (§ item 2a) is fail-SAFE for the fire but fail-CLOSED for the relogin.**
  It NEVER blocks or aborts a fire (best-effort). The headless Phase-1 relogin acts ONLY on provably
  recoverable state (a readable refresh token, zero live sessions, its own account lock) via the
  official binary — never a raw refresh-token POST, never under a live CC. A logged-out / revoked
  account is SURFACED (a `## ACCOUNT STATE` bridge line), never force-fixed. Leave `CC_HEAL_LOCK_PREFIX`
  at its default in production — it MUST equal `claude-accounts` heal()'s lock path or the interlock breaks.
- NEVER write the bridge into a tracked/repo path or commit it. Stateless → `/tmp` only.
- It's a pointer: reference the plan's section; don't restate its body (that's the staleness trap).
- If durable state isn't captured in the plan yet, update the plan FIRST, then emit the bridge.
- **Mode B/C self-test before emitting:** could a brand-new session, knowing ONLY the paste, reach
  every referenced doc + a green baseline with zero pre-work? If any step needs this session's
  context, an unpushed-and-unreachable doc, or a SHA a rebase will move — fix it, then emit.
- **Mode C anchor:** the frozen `handoff/<slug>` branch is the durable ref (in git); the `/tmp`
  bridge stays the disposable pointer. Never point a fork at a live working branch (it moves as you work).
- **Self-locate test (every bridge):** the paste's FIRST line must let a session that opened in the
  WRONG cwd/worktree reach the right one with ONE command — never a scan. Abs worktree path leads
  (`cd`); branch is the cross-clone fallback (`git checkout`, which COLLIDES if run from another linked
  worktree of the same repo — that's *why* the abs path leads); commit is informational (rebase-mobile).
- **Paste-boundary test (every bridge):** the paste payload sits between two VISIBLE labeled rule lines
  (`─` U+2500, "copy from here" / "to here"), fence tight inside them — first payload line the self-locate
  header, last the final payload line, no blank padding between the rules, nothing indented. The Mode
  framing and the "regenerable / what's captured durably" notes stay OUTSIDE the rules.
