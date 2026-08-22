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
