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

## RESOLVED — the gate, read out of 2.1.220 and then measured against it

Three functions decide everything (`claude.exe`, offsets ~231.83M / ~238.15M):

```js
function Dpr(e){ let t=Uon(e); return Rt().projects?.[t]?.hasTrustDialogAccepted===!0 }
function wB(e){ return Dpr(e??gn()) }                      // is THIS cwd trusted, per .claude.json

function ny_(e){ …
  let r=!ynt(), n=yTe({onIndeterminate:"tracked"});
  for(let o of wC()){
    if(o==="projectSettings"&&r)continue;                  // ← project settings SKIPPED
    if(o==="localSettings"&&n)continue;                    // ← settings.local.json SKIPPED
    let i=Hr(o); if(!i)continue;
    if(i.enableAllProjectMcpServers)return!0;
    if(i.enabledMcpjsonServers?.some((s)=>f4r(s,e)))return!0 }
  return!1 }

function SZr(e){ let t=us();                               // us = eo = MERGED settings
  if(t?.disabledMcpjsonServers?.some((r)=>f4r(r,e)))return"rejected";   // ← FIRST, before trust
  if(!wB())return ny_(e)?"approved":"pending";
  if(t?.enabledMcpjsonServers?.some(…)||t?.enableAllProjectMcpServers)return"approved";
  return"pending" }                                        // "pending" ⇒ the modal
```

Four load-bearing consequences — and V2 corrects a working assumption of this document's first draft:

| # | Verdict | |
|---|---|---|
| V1 | **Trust gates the approval sources.** `wB()` false ⇒ `ny_()`, which skips `localSettings`. That is exactly why M5's approval was inert under M6's untrusted record — the root-cause chain above, now read rather than inferred. | [M] binary |
| V2 | **The store is the MERGED SETTINGS, not `.claude.json`.** `us()` = `eo()` = `Aoe().settings`. The `enabledMcpjsonServers` / `disabledMcpjsonServers` keys that exist inside `.claude.json`'s `projects[<cwd>]` entries — the ones M2 measured as empty — **are never read by this gate**. A seed there, which is what the fix's first design proposed, would have been a silent no-op. | [M] binary |
| V3 | **A rejection silences the question and grants nothing.** `disabledMcpjsonServers` is checked *before* the trust branch and returns `"rejected"` outright. So "decided, and the answer is no" is expressible — precisely the answer a `--strict-mcp-config` fire has already given. | [M] binary + probe |
| V4 | **`flagSettings` is always an allowed source** (`wC()` does `t.add("flagSettings")` unconditionally), and `--settings <file-or-json>` IS that source. So the decision can ride the launch instead of being written to any config. | [M] binary + `--help` |

### The A/B, with a positive control

cwd `/private/tmp/mcp-decide-probe`, a `.mcp.json` declaring two fake stdio servers, config dir
`.claude-tertiary`, binary 2.1.220:

| Arm | `claude mcp list` | Server processes spawned |
|---|---|---|
| **no flag** (positive control) | both `⏸ Pending approval (run \`claude\` to approve)` | — |
| `--settings '{"disabledMcpjsonServers":["probeA","probeB"]}'` | **both absent entirely**; the account's five user-scope servers still listed and connected | **none** |
| `--settings '{"enabledMcpjsonServers":["probeA","probeB"]}'` | both approved, real connection attempted (`connection timed out` — the fake speaks no MCP, which is the point: the approval path reached the wire) | yes |

The control matters: without the first row, a green second row would prove only that the probe could
not see anything.

### …and `mcp list` is not the modal — the LIVE TUI arm

The table above reports the *status the gate computes*. It does not prove what the interactive UI
draws, and the whole defect is a drawn dialog. `scripts/mcp-modal-probe.py` closes that: it builds
its own fixture, launches a real TUI on a pty, reads the screen, kills it, and asserts three arms.
Re-runnable after any binary upgrade (`PROBE_CLI` / `PROBE_CFG` / `PROBE_DIR` override).

| Arm | dialog on screen? |
|---|---|
| **no flag** (positive control) | **YES** — captured verbatim: *"2 new MCP servers found in this project / Select any you wish to enable."* |
| **`--strict-mcp-config` alone** | **YES** — the operator's screenshot, reproduced. The isolation flag does not suppress the question it has already answered. |
| **`--settings '{"disabledMcpjsonServers":…}'`** (the fix) | **no** — and the session emitted 3× the bytes of the two blocked arms, i.e. it got *past* the dialog into startup rather than dying earlier. |

Arm 3 is what makes arm 2 mean something: it proves the detector still fires when the dialog is
there, so arm 2's silence is the dialog's absence and not the instrument's.

🚨 **The first version of this probe reported `modal=no` on ALL THREE arms** — including the control.
The Ink TUI renders the dialog one word at a time with a cursor-column escape between every word
(`2\x1b[5Gnew\x1b[9GMCP\x1b[13Gservers…`), so a grep for the literal sentence matches nothing while
the dialog is plainly on screen. Had the control been omitted, that run would have read as *"the fix
works"* — from an instrument that could not have seen a failure. The detector now strips escapes and
collapses whitespace before matching. Same family as the standing lesson that a literal TUI phrase is
a width-dependent anchor — except the breakage here is per-WORD, not per-wrap, so even a
short-phrase anchor would have failed.

## What shipped

| Commit | Change |
|---|---|
| `0d8973832` | **The plain recycle now pre-trusts.** It was the one fire path that skipped `pre_trust`, on the premise M6/M7 refutes. Two tests — the dry-run announcement, plus a structural one pinning the real call site, because the announcement and the call live in different branches and the first alone would pass a revert. |
| `7f3cd743` | **`cc_mcp_project_decision_args`** (`scripts/lib/mcp-noinherit.sh`) composes `--settings=<per-launch file>` naming every server the launch dir's `.mcp.json` declares, with the polarity of the fire's own MCP mode: `--strict-mcp-config` ⇒ rejected, `--with-mcp` (or a brief that disarmed no-inherit) ⇒ approved. Wired into `handoff-fire.sh` beside the existing MCP flags; the library is now sourced on BOTH branches, since a `--with-mcp` fire is the one whose servers actually reach the approval gate. Kill switch `CC_MCP_DECIDE=off`. 8 tests. |

Nothing durable is written by the second change: no account `settings.json`, no `.claude.json`, no
repo file. A later operator session in the same repo sees exactly what it saw before.

**Why not the alternatives** — each rejected for a named reason, so the next reader does not re-open
them: `enableAllProjectMcpServers` in an account settings file is a forever-grant to every repo that
ever declares a server (the MUST-REACH-OPERATOR classification exists to keep it out);
`disabledMcpjsonServers` in an account settings file is account-global, blinding that account to a
server *name* in every repo; writing the launch dir's own `.claude/settings.local.json` leaks the
decision into the operator's own account, because that file is shared by all five.
