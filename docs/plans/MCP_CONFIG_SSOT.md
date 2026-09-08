---
status: open
---

# MCP server config — ONE source of truth, pointed at by every account

## Phase 0 — Agent Team Orchestration

- **WAVE 1 — RESEARCH. EXECUTION LOCUS: S** (dispatched handoff session) running its own **Dynamic
  Workflow / research-subagent fan-out**. Operator directive 2026-08-15, verbatim: *"ensure it does
  its own Dynamic Workflow / research subagent session to investigate the 100th percentile approach
  before diving into implementing."* This wave writes **NO tracked file except this plan**. It ends
  with a scored recommendation in § Wave 1 output, not a diff.
- **WAVE 2 — IMPLEMENTATION. EXECUTION LOCUS: S** (same dispatched session, after Wave 1 lands its
  recommendation). One serial chain on shared config — it does not decompose into independent files,
  and a second writer on the same config surfaces would collide. No teammates.
- **Roster:** one dispatched session, which itself fans out research subagents in Wave 1.
- **Dependency graph:** strictly serial — research (1) → recommendation recorded in this plan (2) →
  operator-visible go/no-go on any destructive step (3) → implement (4) → regression-test (5) →
  land (6). **Wave 2 must not start before Wave 1's recommendation is written into this plan.**
- **Worktree:** repo work in a worktree; but the *config dirs it edits* (`~/.claude*`) are global and
  outside any worktree — a worktree isolates the launcher change, NOT the config change. Treat every
  `~/.claude*/.claude.json` write as touching live global state with no rollback but the backup.
- **Lead context budget / succession:** the originating session (`~/Development/personal`, iPhone
  Messages work) holds ≥50% and does NOT follow this work. This session owns it to completion.

**Created:** 2026-08-15 · **Origin:** an iPhone-Messages MCP install in `~/Development/personal`
needed the same server on every account, and the manual sync **silently missed one of five config
dirs** — see § Why this exists.

## Scope (frozen)

MCP server definitions live in exactly **ONE** file. Every account (`claude`, `claude1`, `claude2`,
`claude3`, `claude4`) and every directory resolves its servers from that file, so adding, changing,
or removing a server is a **one-file edit that cannot diverge** — proven by a fresh session on each
account listing the same server set, and by `tests/claude-launcher-router.bats` staying green.

Per-project `.mcp.json` layering MUST keep working. This is a de-duplication of the *user-scope*
copies, not an abolition of project scope.

## Why this exists — the failure already happened, twice, measurably

**Divergence #1 — `ms365` is defined twice with DIFFERENT endpoints.** Claude Code prints this at
startup, on every session, in `~/Development/personal`:

```
[Conflicting scopes] Server "ms365" is defined in multiple scopes with different endpoints:
  user    (/Users/chrisren/Library/Application Support/fnm/aliases/default/bin/ms-365-mcp-server)
  project (npx -y @softeria/ms-365-mcp-server)
OAuth tokens are stored per endpoint, so authenticating in one context will not carry over.
```

Two endpoints, two token stores, one server name. That is not a hypothetical — it is a live
authentication split. It is also the same class of failure that
[`MS365_MCP_ALL_ACCOUNTS.md`](./MS365_MCP_ALL_ACCOUNTS.md) (open, created the same day) is chasing
from the other end. **Read that plan before acting; the two overlap and must not fight.**

**Divergence #2 — the manual sync missed a dir, within minutes of being written.** On 2026-08-15 a
`mac-messages` server was installed with a loop over what was believed to be all four account dirs.
There are **five** dirs holding an `oauthAccount`. `~/.claude-next` — the `claude1` account, per
`lib/claude-launcher.zsh:211` — was not in the loop:

| Config dir | Account | mac-messages | ms365 |
|---|---|---|---|
| `~/.claude` | default/unpinned | ✅ | ✅ |
| **`~/.claude-next`** | **`claude1`** | ❌ **MISSED** | ✅ |
| `~/.claude-secondary` | `claude2` | ✅ | ✅ |
| `~/.claude-tertiary` | `claude3` | ✅ | ✅ |
| `~/.claude-quaternary` | `claude4` | ✅ | ✅ |
| `~/Development/personal/.mcp.json` | project | ✅ | ✅ (different endpoint) |

**Six copies of the same server definition.** The miss was found only because this plan was being
written; nothing would have surfaced it otherwise — a `claude1` session simply would not have the
tool, silently, and the user would conclude the feature was broken.

**That is the whole argument.** The failure mode is not "someone was careless." It is that N copies
with no SSOT diverge by construction, and the divergence is *silent* — a missing MCP server produces
no error, just an absent capability.

## The mechanism — native, already shipped, no invention required

`claude --help` on 2.1.220 exposes:

```
--mcp-config <configs...>   Load MCP servers from JSON files or ...
--strict-mcp-config         Only use MCP servers from --mcp-config, ignoring all other MCP configurations
```

The launcher at `lib/claude-launcher.zsh` **already wraps every single launch** — it routes
`CLAUDE_CONFIG_DIR` per account (`_cc_install_router`, `claude1()` at :211). That is the natural
chokepoint: one flag, appended there, reaches every account by construction.

**Ruled out, measured 2026-08-15 — do not re-investigate without new evidence:**

| Candidate | Verdict |
|---|---|
| A wider `--scope` | ❌ only `local`, `user`, `project` exist |
| Managed/enterprise settings | ❌ `/Library/Application Support/ClaudeCode/` does not exist on this box |
| `mcpServers` in `settings.json` | ❌ no `settings.json` on this machine defines it; not a supported key |
| An env var for extra MCP config | ❌ none found in the 2.1.220 `cli.js` strings |
| Symlink the `.claude.json` files together | ❌ **actively harmful** — that file carries auth, history, and project state; symlinking collapses account isolation, which the SessionStart hook explicitly maintains ("auth/.claude.json/sessions isolated") |

## 🚨 WAVE 1 — RESEARCH FIRST. Do not write an implementation line until this lands.

The mechanism above is *identified*, not *designed*. Fan out research subagents / a Dynamic Workflow
and answer these before touching anything. The operator asked specifically for the **100th-percentile**
approach, so the bar is "what would we wish we had built in six months," not "what works today."

1. **Does `--mcp-config` merge with, or replace, the config-dir servers?** Read the 2.1.220 binary and
   verify empirically with a throwaway config. The whole design turns on this. If it MERGES, the user
   copies must be stripped or they still diverge. If it REPLACES, project `.mcp.json` layering may
   already be lost without `--strict` — which would be disqualifying.
2. **Does `--strict-mcp-config` kill project `.mcp.json`?** If yes, it is unusable here (scope says
   project layering must survive). Confirm rather than assume; find the precedence order.
3. **Is the launcher the right chokepoint, or is there a lower one?** `handoff-fire.sh`,
   `cc-dispatch`, cron, `--cloud`, and MCP-less headless probes all start sessions. A launcher-only
   fix leaves every non-launcher entry point on the old path. `docs/research/R8-entrypoint-audit.md`
   exists — start there.
4. **What already governs this?** `tests/mcp-no-inherit.bats` and `tests/session-start-mcp-probe.bats`
   exist and encode decisions someone already made about MCP inheritance. **Read them first** — there
   may be a deliberate reason inheritance was prevented, and this plan may be about to undo it.
5. **How does this interact with `MS365_MCP_ALL_ACCOUNTS.md`?** Both are open, both touch the same
   four/five config dirs, both created 2026-08-15. Decide explicitly: does this plan SUPERSEDE it,
   subsume it, or run beside it? Do not leave two plans racing on one surface.
6. **What is the migration's failure mode?** Stripping `mcpServers` from five live `.claude.json`
   files is destructive and touches auth-adjacent state. What is the rollback? What proves success
   *per account* before the next is touched?
7. **Does the SSOT file want to be tracked in this repo or live in `~/.claude/`?** Tracked = reviewable,
   versioned, but needs an install/symlink step and can go stale like the five-week-old
   `worktree-pool.sh` fork documented at `lib/claude-launcher.zsh:~215`. Untracked = live but
   unreviewable. Pick with that precedent in mind.

**Wave 1 output goes in a new `## Wave 1 — research findings` section of THIS file**: the scored
recommendation, the rejected alternatives with reasons, and a go/no-go on each destructive step.
Then implement.

## Wave 1 — research findings

**Run 2026-09-08** against the LIVE binary **2.1.260**. Every number in § The mechanism above was
measured on **2.1.220** and 2.1.260 ships a *compiled* `bin/claude.exe` (198 MB) with no `cli.js`,
so nothing here is a source read — it is all empirical, via a harness described below.

**Execution note (honest):** the mandated fan-out was fired as 7 subagents; the machine's
capacity gate refused 5 of them (16 sessions mid-turn against a ceiling of 8). Axis C (governance)
and axis G (adversarial) ran as subagents; axes A, B, D, E, F were run serially on the lead, per
the gate's own instruction not to retry-storm it. Artifacts:
`scratchpad/wave1/{A-flag-semantics,C-governance,BDEF-lead,G-adversarial}.md`.

### The harness — and why the obvious instrument is blind

`claude mcp list` reports the **same set under every flag combination**. Anything concluded from it
about `--mcp-config` is wrong. The working probe instead makes each server a shell script that
`touch`es a marker file and then `exec`s `/bin/cat`, so the marker records that the server was
actually **started**. MCP servers start *before* the auth check, so an unauthenticated throwaway
`CLAUDE_CONFIG_DIR` under `/tmp` is a sufficient, hermetic harness — observed: `Not logged in ·
Please run /login` **and** both markers written. No live config dir was read or written.

### Answers to the seven questions

**1. `--mcp-config` MERGES — it does not replace.**

| invocation | servers actually STARTED |
|---|---|
| no flags | user + project |
| `--mcp-config=extra.json` | user + project + **extra** |
| `--strict-mcp-config` alone | **NONE** |
| `--mcp-config=extra.json --strict-mcp-config` | **extra only** |

⇒ injecting the SSOT alone de-duplicates nothing; the six user-scope copies keep being read and keep
diverging. DoD #2 is therefore load-bearing, exactly as the plan assumed.

**2. `--strict-mcp-config` KILLS project `.mcp.json` — DISQUALIFYING as a launcher default.** Row 4
above: with strict, the project server did not start. Bare strict is worse — zero servers. The frozen
scope requires project layering to survive, so strict cannot ride on the launcher.

**Also measured — precedence on a name collision** (same name defined in all three):
**`--mcp-config` > project `.mcp.json` > user-scope `.claude.json`.** This is a semantic change the
plan did not state: an SSOT injected by flag **overrides a project's own definition of the same
name**. Additive project servers still layer; a project can no longer *redefine* a shared name.

**Two mechanical traps, both confirmed:** `--mcp-config` is **variadic** in its space form and eats
the next argument (`--mcp-config X mcp list` → `MCP config file not found: …/mcp`) — always use the
`=` form, the same trap already recorded at `03ae59251`. And `${VAR}` in a server's `command` **is**
expanded, so a tracked SSOT can hold a future secret by env indirection.

**3. The chokepoint is NOT the tracked launcher.** `lib/claude-launcher.zsh` is only a *router* — it
composes no binary argv at all. The real launcher body is **`~/.zshrc:451`, untracked**, ending at
`:500` in `"$HOME/.claude/bin/cc-close-attrib" "$_bin" … "$@"`. So the only tracked chokepoint is
**`bin/cc-close-attrib`** (`exec "$REAL_BIN" "$@"` at :316), which every interactive launcher and
every `handoff-fire.sh` fire passes through. Two paths still bypass it: `hooks/session-start.sh:270`
and `lib/cc-upgrade-gate/check13_mcp.sh:14`. Argv is also a *sensed* surface —
`bin/cc-ignition-gate:142` matches on it and `bin/cc-reaper:2836` pins the wrapper shape — so any
injection is observable by two sensors that would need re-checking.

**4. `mcp-no-inherit` is not contradicted, but three mechanisms are** (axis C, full detail in
`scratchpad/wave1/C-governance.md`). "No-inherit" (`ff49e1e36`, 2026-08-11) means a *fired* session
must not start the **project-scope** stdio servers of the repo it lands in, because a headless worker
loads them without consulting any approval list (312 MB per chrome-devtools chain). The motive is
RAM, and it deliberately *preserves* user-scope servers — which is why it composes
`--strict-mcp-config` **plus** a `--mcp-config=` passthrough rather than the bare flag. The couplings:
- **C1 — the strip deletes the passthrough's only input, and the suite stays GREEN.**
  `cc_mcp_noinherit_args` builds that passthrough by reading `$cfg/.claude.json .mcpServers`. DoD #2
  empties it ⇒ `pass=""` ⇒ **bare** strict ⇒ every fired session gets *zero* MCP servers. A test
  asserts that degraded path as correct, so DoD #6 cannot detect the regression.
- **C3 — DoD #2 contradicts a landed, tested, installer-enforced decision** (`ms365-mcp-wire.sh` +
  `install.sh:618-628`); any strip is undone by the next `install.sh`.
- **C5 — the two binary-direct callers** above turn into a confident wrong number and a permanent
  silent SKIP.
- `tests/claude-launcher-router.bats` has **zero argv assertions** (its stub discards `"$@"`), so it
  would not catch a botched append either.

**5. This plan SUBSUMES `MS365_MCP_ALL_ACCOUNTS.md` — the fork is settled.** That plan already built
the mechanism this one needs, for one server: `scripts/ms365-mcp-wire.sh` (170 ln, tracked, wired
into `install.sh:610-630`) enumerates config dirs from tracked `accounts.json`, **merges exactly one
key** under `.mcpServers`, writes via temp + `mv` in the same directory (atomic; never truncates a
file a live session is reading), and is idempotent and `--check`-able. Its header already establishes
why `config-mirror.zsh` structurally *cannot* carry this: `.claude.json` is in `_CC_ISOLATE` because
it races between concurrent processes. Generalising that script from one hardcoded server to a
declarative list is this plan's implementation.

**6. The migration surface is clean — and its mutation mechanism already exists.** A recursive key
search over all six files finds `mcpServers` at 49–120 paths each, but **every nested
`projects.<path>.mcpServers` is an empty dict**; there is exactly ONE non-empty top-level
`.mcpServers` per file. Nothing hides below. The rollback is the wire script's own idempotence: it
re-asserts the desired value on every `install.sh`, so "wrong value" is self-healing; only a *removed*
key needs a backup, and a per-file copy before the first write covers it.

**7. A tracked SSOT needs no new deploy machinery.** `accounts.json` is already tracked at repo root
and reaches the live layer as a **per-file symlink** (`~/.claude/accounts.json -> …`), as is
`scripts/`. A tracked `mcp-servers.json` at repo root is read by the installer (`$REPO_DIR/…`) and by
the standalone script (`$(dirname "${BASH_SOURCE[0]}")/../…`) through the identical path, with **zero
new deployed top-level** — so it carries none of the `LIVE_ADDS` "landed but absent" risk a brand-new
deployed directory would. No live MCP definition carries a secret today, and `${VAR}` expansion (Q1
above) covers the future case. **Tracked wins.**

### 🚨 THE VERDICT — the plan's identified mechanism is DISQUALIFIED as specified

`--mcp-config` + stripping the user-scope copies **works for sessions and destroys the machine's only
MCP observability.** The decisive measurement, with user scope and project scope both empty `{}`:

```
$ claude --mcp-config=f1.json mcp list
No MCP servers configured. Use `claude mcp add` to add a server.
$ claude -p ok --mcp-config=f1.json     # marker file written
  → the server STARTED
```

**`claude mcp list` is structurally blind to `--mcp-config`.** Both shipped MCP sensors read exactly
that command — `hooks/session-start.sh:270` and `lib/cc-upgrade-gate/check13_mcp.sh:14`. Under the
flag-injection design they would report **zero servers, permanently and silently wrongly**: the
session-start banner would read "MCP: 0 server(s) connected" forever, and check #13's PASS condition
(≥1 `✔ Connected`) could never be met, blocking the upgrade gate machine-wide. DoD #3 ("a fresh
session on every account resolves the same server set — verified per account") would have **no
instrument left to verify it with**.

That is the same defect class this repo has already paid for twice: a gate keyed on a signal that
cannot observe the phenomenon, and a blind instrument's null read as absence.

### The recommendation — RENDER, don't inject

**Keep the servers where `mcp list` can see them; make the copies GENERATED instead of hand-written.**

One authored file — tracked `mcp-servers.json` at repo root — and one renderer that merges it into
every `.claude.json` that a session can actually read. Concretely: generalise
`scripts/ms365-mcp-wire.sh` from `SERVER_NAME="ms365"` to a loop over that file, preserving every one
of its existing properties (merge-not-write, temp + `mv`, idempotent, `--check`, fail-open, installer
re-assertion). Scored against the alternatives:

| approach | one source? | project layering | `mcp list` truthful | reaches all entry points | verdict |
|---|---|---|---|---|---|
| **render from a tracked SSOT** (recommend) | authored once | untouched | ✅ | ✅ by construction — it edits the config, so there is no chokepoint problem at all | **ADOPT** |
| `--mcp-config` on the launcher + strip | ✅ | ✅ (without strict) | ❌ both sensors lie | ❌ untracked `~/.zshrc`; 2 bypassers; argv is sensed | reject |
| `--mcp-config` + `--strict-mcp-config` | ✅ | ❌ killed | ❌ | ❌ | reject — violates frozen scope |
| symlink the `.claude.json` files | — | — | — | — | reject — collapses account isolation (already ruled out; still true) |
| `config-mirror.zsh` | — | — | — | — | reject — `.claude.json` is in `_CC_ISOLATE` *because* it races |

**Why this is the 100th-percentile answer and not a retreat.** The failure the plan exists to kill is
*silent divergence between hand-maintained copies*. Generation plus a divergence check kills exactly
that, and the plan's own **DoD #7** — "a regression test that FAILS if a server is added to one config
dir and not the SSOT" — only *means* anything if the copies still exist. DoD #7 presupposes the render
model. It also dissolves axes B and C entirely: no argv change, no untracked `~/.zshrc` edit, no
`cc_mcp_noinherit_args` breakage (its input keeps existing), no sensor blinding, and every non-launcher
entry point is reached because the config file itself is what changed.

### 🚨 The bug this research found — divergence #1 has a named cause

`scripts/ms365-mcp-wire.sh` loops over `accounts.json`'s four config dirs **plus `~/.claude`**, on the
comment *"plus `~/.claude` itself (the default dir a bare `claude` uses when `CLAUDE_CONFIG_DIR` is
unset)"*. **That comment is false, measured on 2.1.260:** with `CLAUDE_CONFIG_DIR` unset the binary
reads **`$HOME/.claude.json`**, not `$HOME/.claude/.claude.json`. (Probe: two servers, one in each
file, under a throwaway `HOME` — only the `$HOME/.claude.json` one started.)

So the file the comment is aiming at **is never in the loop**, and today:

```
$ ./scripts/ms365-mcp-wire.sh --check
  ✓ .claude-next: ms365 already correct        ✓ .claude-secondary: ms365 already correct
  ✓ .claude-quaternary: ms365 already correct  ✓ .claude: ms365 already correct
  ✓ .claude-tertiary: ms365 already correct
```

**5/5 green — over a population that excludes the one divergent file.** `~/.claude.json` still carries
`npx -y @softeria/ms-365-mcp-server@latest`, the exact form that script's own header documents as
costing ~116 MB and a registry round-trip per session. The checker's denominator is the defect.

**Divergence #1 is also worse than filed — three endpoints, not two:**

| where | `ms365` definition |
|---|---|
| `~/.claude.json` | `npx -y …@latest`, env `MS365_MCP_TENANT_ID=consumers` |
| the five config dirs | `…/fnm/aliases/default/bin/ms-365-mcp-server`, args `[]`, env **`{}`** |
| `~/Development/personal/.mcp.json` | `npx -y …` (**no `@latest`**), env tenant=consumers |

The empty `env` in the five dirs is functional, not cosmetic — they carry no tenant id. And per the
precedence measurement above, inside `~/Development/personal` the *project's* npx form wins over the
config dir's binary, which is precisely the `[Conflicting scopes]` warning § Why this exists quotes.

### Go / no-go on each destructive step

| step | verdict |
|---|---|
| strip `mcpServers` from the six `.claude.json` files | **NO-GO** — breaks `cc_mcp_noinherit_args` silently (C1), is undone by the next `install.sh` (C3), and blinds both MCP sensors |
| append `--mcp-config` in the launcher | **NO-GO** — the tracked launcher composes no argv; the real one is untracked `~/.zshrc` |
| append `--strict-mcp-config` anywhere on the default path | **NO-GO** — violates the frozen scope (kills project layering) |
| add `~/.claude.json` to the wire script's population | **GO** — additive merge, same atomic path, cures divergence #1 |
| generalise the wire script to a tracked `mcp-servers.json` | **GO** — no new deployed top-level, no argv change, sensors stay truthful |
| edit `~/Development/personal/.mcp.json` | **DEFER** — out of this repo; the conflicting-scopes warning is cured from the user-scope side first, then re-measured |

### What this does to the Definition of done

DoD #2 must be read as **"defined in exactly one AUTHORED place"** — the per-account copies become
build artifacts of the renderer, not sources. DoD #4 (the conflicting-scopes warning) is now known to
need the project file too, so it is re-scoped to *the user-scope halves agree*; the project-scope half
is named in the table above as deferred. Everything else stands unchanged.

## Landmines

- **The launcher is load-bearing for every session on this machine.** Break it and you cannot start a
  session to fix it. Keep a known-good copy reachable, and know how to launch bypassing the wrapper
  (`~/.claude-220/node_modules/.bin/claude` directly) before editing.
- **`claude` in the interactive shell is a zsh FUNCTION, not the binary.** Scripts must use the real
  path or they hit `_claude_pinned: command not found`.
- **The repo checkout is dirty** (21 untracked files at HEAD `3aa963042`, mostly
  `docs/plans/backlog-consolidation-2026-08-09/*.json`) and **is not this session's dirt**. Do not
  sweep it into a commit; `git add` explicit paths only.
- **MCP tools bind at session START.** No config change reaches a running session; every verification
  needs a fresh one.
- **Five dirs, not four.** `~/.claude`, `~/.claude-next`, `~/.claude-secondary`, `~/.claude-tertiary`,
  `~/.claude-quaternary`. Any loop that hardcodes four is already wrong — enumerate by
  "has an `oauthAccount` key", never by a written list. That is the bug this plan exists to kill.

## Definition of done

1. `## Wave 1 — research findings` written into this file, with the recommendation and rejections.
2. MCP servers defined in exactly one place; no user-scope duplicates remain.
3. A fresh session on **every** account resolves the same server set — `mac-messages`, `ms365`,
   `motion`, `motion-plus` — verified per account, not extrapolated from one.
4. The `ms365` conflicting-scopes warning is gone.
5. Project `.mcp.json` layering still works (a project-only server still resolves).
6. `tests/claude-launcher-router.bats`, `tests/mcp-no-inherit.bats`,
   `tests/session-start-mcp-probe.bats` all green.
7. A regression test that FAILS if a server is added to one config dir and not the SSOT.
8. Landed on `origin/main`.

## Status log

- **2026-08-15 — created.** Divergence measured (6 copies of `mac-messages`, `ms365` split across two
  endpoints, `~/.claude-next` silently missed). Mechanism identified (`--mcp-config` + the launcher
  chokepoint); five alternatives ruled out with evidence. Research wave NOT yet run — that is the
  next action, per operator directive.
- **2026-08-22 — RECOVERED to `origin/main`; premise re-measured and it SURVIVES.** This file existed
  nowhere in git for seven days: absent from `origin/main`, absent from the shared checkout's HEAD
  tree, and present only as **untracked** bytes (`git status` → `?? docs/plans/MCP_CONFIG_SSOT.md`)
  plus branch `feat/mcp-config-ssot` (tip `aed9485e1`, ahead 1 / behind 521). The untracked copy was
  byte-identical to the tip (10,914 B both), which is *why* nothing looked broken —
  `docs/research/mcp-modal-fire-stall-2026-08-15.md` (landed 2026-08-16T04:42:36Z) links here as its
  "Companion plan" and cites this file's § Why this exists as evidence for its M4, and open backlog
  row `9f203fa60cd0` carries this path as its `dodRef`; **both were reading a file that one
  `git clean -f -d` would have deleted.** Recovered from the immutable tip sha, not from the
  working-tree copy. Re-measurement, same moment, read-only over the live config dirs:
  - **§ Landmines "five dirs, not four" is EXACTLY TRUE today** — all five of `~/.claude`,
    `~/.claude-next`, `~/.claude-secondary`, `~/.claude-tertiary`, `~/.claude-quaternary` carry an
    `oauthAccount` key. Enumerate by that key, never by a written list.
  - **Divergence #1 (`ms365`, one name / two endpoints) IS STILL LIVE.** `~/.claude.json` registers
    `npx -y @softeria/ms-365-mcp-server@latest`; all five config dirs register the resolved fnm
    binary. Two endpoints ⇒ two OAuth token stores, exactly as the startup warning quoted above says.
  - **Divergence #2's *instance* has vanished, and that is NOT a cure.** `mac-messages` is now absent
    from all six copies — removed everywhere, not unified. Closing this plan on that would be a
    vanished-precondition close; the *mechanism* (N copies, no SSOT, silent divergence) is what
    divergence #1 still demonstrates.
  - Independently corroborated by `docs/research/startup-2026-08-16/measure-mcp-servers.md` (landed
    2026-08-17T05:58:39Z), whose user-scope table records the same `~/.claude.json` `@latest` split
    as its Finding R-1 — a *measurement* of this plan's premise, not an answer to its design fork.
  - **The Wave-1 question 5 fork is still genuinely open on both sides:** this plan's row
    (`9f203fa60cd0`) and `MS365_MCP_ALL_ACCOUNTS.md`'s row (`8079d6039639`) are BOTH still `open`.
    Neither supersedes the other yet. Decide that explicitly before Wave 2, as § Wave 1 item 5 says.

  **Status stays `open`. Nothing in Wave 1 was run** — this was a recovery of the artifact, not
  progress on the work. The next action is unchanged: run the Wave 1 research fan-out.
