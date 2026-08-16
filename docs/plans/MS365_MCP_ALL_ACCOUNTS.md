---
status: open
---

# MS365 / Microsoft Graph MCP — always-on across all 4 accounts

## Phase 0 — Agent Team Orchestration

- **EXECUTION LOCUS: S** (dispatched handoff session) — the default for an implementation wave; the
  originating chris-resume session pays only for this brief. One wave, one session, no teammates:
  the work is a single diagnose→auth→wire→verify chain on shared config, so it does not decompose
  into independent files and a second writer on the same four `.claude.json` surfaces would collide.
- **Roster:** one dispatched session. No teammates (T) and no lead-inline work (L).
- **Dependency graph:** strictly serial — diagnose (1) → auth (2) → confirm cache scope (3) →
  wire 4 dirs (4) → verify per account (5) → land (6). Step 4 must not start before step 1 names a
  cause, or a broken config propagates to four accounts.
- **Worktree:** none. This edits account config dirs and repo config wiring in place; the checkout is
  shared and diverged (see Landmines), so a worktree would not isolate the thing being changed.
- **Lead context budget / succession:** the originating session holds ≥50% and does not follow this
  work; the dispatched session owns it to completion and pings back on the `--notify-back` channel.

**Created:** 2026-08-15 · **Origin:** chris-resume session needed a mailbox search, found no MS365 tool
connected, and discovered the server is configured in only 1 of 4 account config dirs.

## Scope (frozen)

The `ms365` MCP server is CONNECTED AND AUTHENTICATED from a fresh session on **every one of the 4
accounts** (next · next2 · next3 · next4), durably — surviving new sessions, new worktrees, and a
re-run of `install.sh` — proven by listing an `ms365` mail tool from a session on each account.

## Why this exists

A 2026-08-14 session searched Chris's mailbox via MS Graph ("read-only search via MS Graph", recorded
in `chris-resume/evidence/07-web3-outlook.md`) across three aliases — `ren.chris@outlook.com`,
`chris.swe@outlook.com`, `ichris96@hotmail.com`. On 2026-08-15 the same capability was unavailable:
no `ms365` tool surfaced, so a mailbox question could not be answered. The capability exists but is
not durable.

## Measured starting state (2026-08-15, read live — re-verify before acting)

**The server is already configured, just not everywhere and not connecting.**

| Config dir | Account | `mcpServers` | ms365? |
|---|---|---|---|
| `~/.claude-next` | next (`claude`) | motion, motion-plus, **ms365** | ✅ |
| `~/.claude-secondary` | next2 (`claude2`) | motion, motion-plus | ❌ |
| `~/.claude-tertiary` | next3 (`claude3`) | motion, motion-plus | ❌ |
| `~/.claude-quaternary` | next4 (`claude4`) | motion, motion-plus | ❌ |

Also present in the legacy `~/.claude.json` (the home-dir file, NOT `~/.claude/`).

Server config, identical in both places:

```json
{ "type": "stdio", "command": "npx", "args": ["-y", "@softeria/ms-365-mcp-server@latest"], "env": {} }
```

**The `.claude-next` case is the important one: ms365 IS configured there, and it still did not
connect** in a live session on that account (5 servers connected; no `ms365` tool resolvable via
ToolSearch). So this is NOT purely a "copy the config to 3 more dirs" job — there is a real
connect/auth failure to diagnose first. Copying a broken config to three more accounts would produce
four broken accounts.

Token-cache surfaces seen: `~/Library/Application Support/ms-365-mcp-server` (exists), and
`~/.ms-365-mcp-server/logs` (dirs dated Apr 26 / May 24 2026 — likely a stale or expired auth).

Note there is a SECOND, unrelated mail path: the `outlook-cleanup` skill uses its own MSAL device-code
token cache and `python pipeline.py auth`. Do not conflate them. This plan is only about the MCP server.

## Work

**Step 0 — setup / baseline.** `cd ~/Development/claude-infrastructure`. Re-run the table above and
confirm it still holds. Read `install.sh:348-360` and `:456` for how `config-mirror.zsh` decides what
each account config dir SHARES vs owns — that is the durability mechanism.

1. **Diagnose the connect failure on `next` first.** Run the server by hand
   (`npx -y @softeria/ms-365-mcp-server@latest`) and read its startup output. Establish whether it is
   (a) unauthenticated / expired token, (b) an npx resolution or version problem, (c) a missing
   `env` entry the package now requires, or (d) something else. Name the cause before fixing.
2. **Authenticate.** The softeria server exposes a login/device-code flow. Complete it.
   🚨 **If it needs an interactive browser or device code, that is CHRIS's step, not yours** — write
   it to one `/tmp/ms365-auth.sh` with per-step comments, open with `cursor`, and hand it over per the
   `manual-command-delivery` skill. Do not attempt to drive an interactive login headlessly.
3. **Verify the token cache is shared, not per-account.** The cache lives under
   `~/Library/Application Support/ms-365-mcp-server`, i.e. it is keyed to the macOS user, not to a
   Claude config dir — so ONE auth should serve all four. CONFIRM this rather than assuming it; if it
   turns out to be per-config-dir, the auth step repeats per account and the plan grows.
4. **Wire it into all 4 dirs durably.** Prefer `config-mirror.zsh` (the sanctioned mechanism) over
   hand-editing four `.claude.json` files — hand-copies drift, which is exactly how it ended up in 1
   of 4. If the mirror is the wrong layer, say why in the status log and use `install.sh`.
5. **Verify per account.** From a session on EACH launcher (`claude`, `claude2`, `claude3`, `claude4`),
   confirm an `ms365` mail tool resolves. This is the DoD evidence — paste the output.
6. **Land** per this repo's normal flow, and update the status log below.

## Landmines

- 🚨 **This checkout is DIVERGED: `main...origin/main [ahead 1, behind 59]`** (measured 2026-08-15).
  A peer session (`recycle-subagents-44`) filed backlog `d8bf32ab63ef` for a hard reset of this
  SHARED checkout — 8 sessions use it, so the reset is Chris's call and is NOT yours to run. Work
  around it; do not `git reset --hard` this tree.
- Untracked files present (`accounts.json.pre-router.*`, a backlog json) — leave them; they are not yours.
- `~/.claude.json` (home-dir file) and `~/.claude/` (default config DIR) are DIFFERENT surfaces and
  both exist. A check that reads the wrong one reports the wrong answer — this cost a wrong reading
  during intake.
- `accounts.json` is the identity SSOT and is a SYMLINK to this repo. Never write secrets into it —
  OAuth tokens belong in the Keychain.
- Account dir names do NOT follow the launcher names: next2/3/4 are `secondary`/`tertiary`/
  `quaternary`, not `.claude-next2/3/4`. Anything iterating `~/.claude-next{2,3,4}` silently matches
  nothing — verify against `accounts.json`, never guess the path.

## Definition of done

- [x] Root cause of the `next` connect failure named in the status log (not just "fixed").
      → `--strict-mcp-config` + a passthrough whose jq filter drops all stdio servers.
- [x] `ms365` present in all 4 account config dirs, via a durable mechanism, not hand-copied.
      → `scripts/ms365-mcp-wire.sh`, idempotent, run by `install.sh`; 5 dirs incl. `~/.claude`.
- [x] An `ms365` mail tool resolves from a session on each of the 4 launchers — output pasted.
      → `mcp__ms365__list-mail-folders` → 10 folders, on all four. Output above.
- [x] Survives a re-run of `install.sh`.
      → wired as an install step; re-run is a no-op reporting "already correct".
- [x] Any interactive auth step Chris must run is delivered as one commented `/tmp/ms365-auth.sh`.
      → **N/A, resolved not skipped:** the token cache is valid (`verify-login` succeeds for
      `ren.chris@outlook.com`), so there is no interactive step and no script to hand over.

**Not closed by this work (named, not hidden):** newly *fired* peer sessions still lack ms365 until
the shared checkout fast-forwards — see the KNOWN REMAINING GAP in the status log. Desk sessions on
all four launchers, which is what the DoD asks for, are verified working.

## Status log

- **2026-08-15 — created.** Starting state measured (table above). Not started.

- **2026-08-15 — ROOT CAUSE NAMED (step 1 done). It is not auth, and it is not the server.**

  **The cause: every fired session launches with `--strict-mcp-config`, pointed at a generated
  passthrough file that filters out exactly one class of server — stdio — and ms365 is stdio.**

  Measured argv of a live session on `next`:

  ```
  claude --permission-mode auto --model claude-opus-5 --effort high \
         --strict-mcp-config --mcp-config=/var/folders/.../T//cc-mcp-userscope-.claude-next.json
  ```

  `--strict-mcp-config` means the session's MCP servers come **only** from that file. The
  `mcpServers` block in `~/.claude-next/.claude.json` is therefore *structurally invisible* to the
  session — which is why ms365 could be correctly configured there and still never appear.

  The file is generated by `scripts/lib/mcp-noinherit.sh:83`:

  ```
  jq '{mcpServers: ((.mcpServers // {}) | with_entries(select(.value.command == null)))}'
  ```

  `select(.value.command == null)` keeps only servers with **no `command` key** — i.e. http/sse
  only. ms365 is `{"type":"stdio","command":"npx",...}`, so it is dropped. Contents of the live
  file: `motion`, `motion-plus`, and nothing else.

  **Why the filter is wrong, precisely.** The control exists (backlog `eece54939e7f`) to stop a
  fired worker inheriting a *repo's project-scope* `.mcp.json` stdio servers. But project scope is
  already excluded by construction — `--strict-mcp-config` reads only the passthrough, and the
  passthrough is built from the **account's user-scope** `.claude.json`. Applying the stdio test to
  the user-scope population bans a class the control was never aimed at. Its own header comment
  says so: *"an http server holds no local process, so blocking it saves nothing"* — the reasoning
  is about http vs stdio **cost**, but the test was written against the only population that
  existed when it was measured. Per that header, the three candidate flags were measured against
  *"the account's real user-scope **http** servers (motion, motion-plus)"* — there was no
  user-scope stdio server in the fleet at the time, so a scope-blind stdio ban and a correct
  scope-aware rule were indistinguishable. ms365 is the first user-scope stdio server, and it is
  the case that tells them apart.

  **Second-order finding — the fail-open cannot save this brief.** `mcp-noinherit.sh:69` disarms
  the control when the brief names MCP work, but it matches `mcp__[a-z0-9_-]+|browsermcp|
  chrome-devtools|agent-browser|claude-in-chrome`. This brief says "ms365" and "MCP" but contains
  no `mcp__`-prefixed tool name, so the control stayed armed for the very session fired to fix it.

  **Ruled out, with evidence — none of these is the cause:**

  | Hypothesis | Verdict |
  |---|---|
  | Unauthenticated / expired token | **NO.** `verify-login` → `{"success":true,"userData":{"userPrincipalName":"ren.chris@outlook.com"}}`. `list-accounts` → 1 account, default. **No interactive step is needed from Chris.** |
  | npx resolution / version problem | **NO.** Handshakes clean; `serverVersion` `Microsoft365MCP 0.143.0`. |
  | Missing required `env` entry | **NO.** `env:{}` is sufficient; 188 tools list unauthenticated. |
  | Startup timeout | **NO.** 6.0 s cold / 2.1 s warm vs `MCP_TIMEOUT=30000`. |
  | Tool-list gated behind auth | **NO.** All 188 tools list pre-auth, incl. `list-mail-messages`, `send-mail`. |
  | Server not connecting at all | **NO.** `claude mcp list` → `ms365: ✔ Connected`. It connects on demand; it is never *offered* to a session. |

  Discriminating evidence: `mcp-logs-ms365/` has **no log line for this session's id**, while
  `mcp-logs-motion/` does. The server was never launched for the session — not launched and failed.

  **Cost measured, because it decides the fix's shape.** `npx -y ...@latest` costs **two** node
  processes: an `npm exec` wrapper (115.6 MB) plus the server (139.3 MB) = **~255 MB per session**.
  At 16 live sessions that is ~4 GB, on a box with a documented memory-storm panic history
  (task #151). Installing the package and invoking its binary directly drops the wrapper process
  entirely (~255 MB → ~139 MB, −45%) and removes the `@latest` registry round-trip that costs the
  6 s cold start. The fix therefore pins the version and calls the binary, rather than npx-ing
  `@latest` on every session start.

  **WHICH SESSIONS THE BUG ACTUALLY HIT — the refinement that decides the fix's shape.** Only
  `scripts/handoff-fire.sh` composes these flags (`handoff-fire.sh:7051,7061`). The desk launcher
  `claude()` in `~/.zshrc` carries **no MCP flag at all** — grepped over the whole function body.
  So the two populations differ:

  | Session kind | Reads | Was ms365 reachable? |
  |---|---|---|
  | **Desk** (`claude`, `claude2`, `claude3`, `claude4`) | `.claude.json` directly | Yes — wherever the config had it. It was in 1 dir of 4, so three accounts had nothing to read. |
  | **Fired peer** (`handoff-fire.sh`) | ONLY the passthrough | **No — on every account, including the one configured correctly.** |

  That is why the capability read as intermittent rather than broken: the 2026-08-14 session that
  did successfully search the mailbox was a **desk** session on `next`, the one dir carrying the
  entry. The fix therefore needs BOTH halves — the config in all four dirs (desk) and the allowlist
  (fired) — and either alone leaves half the fleet blind.

  **`config-mirror.zsh` is the WRONG layer for this** (the plan's step 4 asked to say why if so).
  `.claude.json` is in the isolate-set of **all four** account dirs — it is the one file the mirror
  deliberately refuses to share, because it races between concurrent Claude Code processes. The
  mirror can therefore never carry `mcpServers`. Durable wiring goes in `install.sh`, as an
  idempotent per-account merge that preserves each dir's own state.

- **2026-08-15 — BUILT + VERIFIED (steps 2-5).** No interactive auth was needed: the token cache
  was already valid, so DoD item 5 (`/tmp/ms365-auth.sh` for Chris) is **not applicable** — there
  is nothing for Chris to run. Recording that as a resolved question rather than an unmet box.

  **Changes**

  1. `scripts/lib/mcp-noinherit.sh` — user-scope stdio **allowlist**
     (`CC_MCP_USERSCOPE_STDIO_ALLOW`, default `ms365`). Deliberately an allowlist, not a deletion of
     the stdio filter: a user-scope stdio server is a real ~139 MB/session cost, so the default
     stays "deliberately named servers only". Setting it empty restores the old behaviour exactly,
     and that empty case is the suite's control.
  2. `scripts/ms365-mcp-wire.sh` (new) — idempotent per-account merge into every `config_dir` from
     `accounts.json` plus `~/.claude`. Adds one key under `.mcpServers`, preserves all other
     per-account state, temp+`os.replace` so a live session never sees a truncated file. `--check`
     reports per-dir state and writes nothing. It also asserts the allowlist is present in
     `mcp-noinherit.sh` — wiring the config without it reproduces this exact bug.
  3. `install.sh` — runs the wire script on every install (`--dry-run` → `--check`), so the 1-of-4
     drift cannot silently return.
  4. Package installed at the fnm `aliases/default` path and invoked directly, replacing
     `npx -y …@latest`. Removes the wrapper process and the per-start registry round-trip.

  **A bug caught by RUNNING the jq, not reading it.** The first allowlist expression was
  `($a | index(.key))`. The pipe rebinds `.` to the array, so `.key` indexes an array with a string
  and jq aborts — which fails the whole filter, leaves the passthrough empty, and falls through to
  **bare** `--strict-mcp-config`, dropping *every* server including the http ones the passthrough
  exists to preserve. The symptom would not have been "ms365 missing" but "motion missing too".
  Correct form binds first: `(.key as $k | $a | index($k))`. Pinned by its own regression test.

  **Verification — `tests/mcp-no-inherit.bats` 13/13 green** (1 opt-in live probe skipped), 4 cases
  new. Mutation-proved: forcing the pre-fix behaviour fails the ms365 case at the asserted line, so
  the control can fail.

  **DoD evidence — one real session per launcher, each calling an ms365 mail tool:**

  ```
  --- next2 (launcher claude2, dir .claude-secondary)
  mcp__ms365__list-mail-folders 10
  --- next  (launcher claude,  dir .claude-next)
  mcp__ms365__list-mail-folders 10
  --- next3 (launcher claude3, dir .claude-tertiary)
  mcp__ms365__list-mail-folders 10
  --- next4 (launcher claude4, dir .claude-quaternary)
  mcp__ms365__list-mail-folders 10
  ```

  **KNOWN REMAINING GAP — the fired-session half is landed but not live, and it is blocked on the
  divergence that is Chris's call.** `~/.claude/scripts/lib/mcp-noinherit.sh` is a symlink into the
  **shared checkout**, which sits `ahead 1, behind 59` of `origin/main` (backlog `d8bf32ab63ef`, a
  peer's reset request — explicitly not this session's to run). So the allowlist reaches the live
  layer only when that checkout fast-forwards. Until then: **desk sessions on all four launchers
  have ms365 (verified above, and that is the DoD); newly fired peer sessions still will not.**
  `scripts/ms365-mcp-wire.sh` is additionally an **ADD**, so it has no symlink at all until an
  `install.sh` runs against a converged checkout — an added file gets no converge budget, it is
  simply absent. Nothing further is available from this session without touching the shared
  checkout, which the brief forbids.
