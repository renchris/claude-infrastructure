# A fired session stalls at the project `.mcp.json` approval modal — root cause and the fix's shape

**2026-08-15.** Operator goal, verbatim: *"ensure our /handoff doesn't get blocked on mcp permission
prompts."* Trigger: a screenshot of a handoff-fired pane in `~/Development/personal` on `claude3`
(`.claude-tertiary`) sitting at

```
2 new MCP servers found in this project
Select any you wish to enable.
  › [✓] ms365
    [✓] mac-messages
 Space to select · Enter to confirm · Esc to reject all
```

with the auto-submitted brief unread behind it. The launch line carried
`--strict-mcp-config --mcp-config=…/cc-mcp-userscope-.claude-tertiary.json` — i.e. **the fire had
already decided these servers would not load, and was asked about them anyway.**

Companion plan: [`docs/plans/MCP_CONFIG_SSOT.md`](../plans/MCP_CONFIG_SSOT.md) (server *definitions*
SSOT — different problem, same surface; do not let the two fight). Prior art this builds on:
[`cc-startup-modals-2026-08-04.md`](./cc-startup-modals-2026-08-04.md) (the modal class + the
MUST-REACH-OPERATOR classification) and
[`mcp-memory-groundup-2026-08-10/04-spawn-semantics.md`](./mcp-memory-groundup-2026-08-10/04-spawn-semantics.md)
(approval mechanics, `-p` bypass).

## Why this is a real class, not one bad pane

A spawned session stopped at a modal **never runs its brief and nothing upstream notices** — the pane
is alive, the process is alive, no hook fires. That is the same blind spot
`cc-startup-modals-2026-08-04.md` was written about. `bin/cc-wedge-watch` (positive UI anchors) is the
detector; this document is about **prevention**, which is the half that does not exist yet.

## Measured, this session

| # | Fact | How |
|---|---|---|
| M1 | `~/.claude-next/settings.json` sets `enableAllProjectMcpServers:true`. `.claude`, `.claude-secondary`, `.claude-tertiary`, `.claude-quaternary` do **not**. | `jq` over all five `settings.json` |
| M2 | Every account's `projects[<dir>]` entry for the repos in question carries `enabledMcpjsonServers:[]` **and** `disabledMcpjsonServers:[]` — i.e. **no per-project decision is recorded anywhere on accounts 2/3/4** | `jq` over five `.claude.json` |
| M3 | Six repos on this box carry a project `.mcp.json`: `personal`, `reso-management-app`, `reso-qa-runner`, `inventory-management`, `taxes-2026`, `technical-analysis` | `ls ~/Development/*/.mcp.json` |
| M4 | `~/Development/personal/.mcp.json` declares exactly the two servers in the screenshot (`ms365`, `mac-messages`) — and `mac-messages` was **added on 2026-08-15**, the day of the stall | file + `MCP_CONFIG_SSOT.md` § Why this exists |
| M5 | `~/Development/personal/.claude/settings.local.json` **already** carries `enableAllProjectMcpServers:true` *and* `enabledMcpjsonServers:["agent-browser","uidotsh","ms365","mac-messages"]`. The modal fired anyway. | `jq` |
| M6 | `.claude-tertiary`'s entry for `/Users/chrisren/Development/personal` has `hasTrustDialogAccepted:false` **and no `hasCompletedProjectOnboarding` key at all** | `jq -r '…\|keys'` |
| M7 | `pre_trust()` writes **both** keys together. Its absence in M6 therefore proves **`pre_trust` never ran for that dir/account pair** — the entry was authored by Claude Code itself | `scripts/handoff-fire.sh:6734` vs M6 |
| M8 | By contrast **314 of 322** `/.worktrees/` entries on `.claude-tertiary` (and 412/413 on `.claude-quaternary`) are `hasTrustDialogAccepted:true` — the worktree fire path pre-trusts reliably | `jq` group-by |
| M9 | `~/Development/reso-management-app/.claude/settings.local.json` also carries `enableAllProjectMcpServers:true` — which is why the fleet's constant fires into reso worktrees (182 in the telemetry) have never surfaced this stall despite reso's `.mcp.json` carrying four servers | `jq` |
| M10 | `claude mcp` exposes no `approve`/`reject` subcommand, and `claude --help` on 2.1.220 exposes no flag that skips the approval question. **Disk state is the only lever.** | `--help` on the live 2.1.220 binary |

## The root-cause chain

1. The vendor drops project-scoped *settings* in a folder the config dir does not record as trusted
   (docs L184, from v2.1.196; `settings.local.json` likewise from v2.1.207).
2. So M5's approval — which would have silenced the modal — was **inert**, because of M6/M7: that
   dir was never pre-trusted **for that account**.
3. With no honored decision, the two `.mcp.json` servers read as *new* ⇒ modal ⇒ the brief is never
   consumed.

**And `--strict-mcp-config` does not save you.** The flag governs which servers *load*; the modal is
a question about the project file. A fire therefore gets asked to approve servers it has already
guaranteed will not run. (Binary-level confirmation of the modal's exact predicate is the open item
below.)

### Why the worktree path is immune and the operator-dir path is not

`pre_trust` is called on the normal fire path (`handoff-fire.sh:8940`) and on a *relocating* or
*account-repicking* recycle (`:8927`) — never on a plain same-pane, same-dir recycle. That omission
was justified as *"the running session in that dir already proves it is trusted"*, and the claim is
about a **config dir**, not a directory. It is also **time-blind**: today's `mac-messages` install
shows a `.mcp.json` can grow a new server under a dir whose trust/approval state was settled long
ago. A decision recorded yesterday does not cover a server added today — which is exactly what
*"**new** MCP servers found"* means.

## The fix's shape (design constraints, before any code)

- **Not `enableAllProjectMcpServers`.** `cc-startup-modals-2026-08-04.md` §1 classifies `.mcp.json`
  approval as MUST-REACH-OPERATOR precisely because that key is a forever-grant to every repo that
  ever declares a server. Nothing here justifies widening it.
- **Seed the decision the fire has already made, per project path, per account** — the same
  chokepoint, canonicalisation (`pwd -P`) and idempotence discipline as `pre_trust`, at the same call
  sites plus the plain-recycle one.
- **Polarity must follow the fire's own MCP mode, never a fixed value.** A no-inherit fire
  (`--strict-mcp-config`, the default) has decided *off* ⇒ record the names as rejected. A
  `--with-mcp` fire, or one whose brief disarms no-inherit because it names MCP work, has decided
  *on* ⇒ record them as enabled. A fixed "reject" polarity would silently hide a server the fire
  itself needs — the exact failure class as the ms365 disappearance
  (`MS365_MCP_ALL_ACCOUNTS.md`), and the reason a scope-blind rule is never acceptable here.
- **Converge, never accumulate.** Each fire re-asserts its polarity so a name is in exactly one list;
  otherwise a stale rejection from an earlier fire outlives its reason.
- **Trust and MCP are two gates, and fixing one does not fix the other.** Pre-trusting the launch dir
  makes an *existing* project-settings approval honored (M5), but only where the repo happens to
  carry one; three of the six `.mcp.json` repos do not. The MCP seed must therefore stand on its own.

## Open — being measured now (three parallel probes)

1. **The modal's exact predicate** in the 2.1.220 binary: which on-disk state it diffs against, and
   whether a *rejection* record suppresses the prompt without granting a load.
2. **Entry-point census**: every path in this repo that launches an interactive session into a dir
   that may carry `.mcp.json` (fire, recycle, repick, `cc-pane-runner`, boot-resume, limit-recover).
3. **Empirical A/B** with a positive control: virgin config ⇒ modal; each candidate pre-seed ⇒ modal
   or not, and did the servers actually spawn.

Findings land in the sections below as they arrive.
