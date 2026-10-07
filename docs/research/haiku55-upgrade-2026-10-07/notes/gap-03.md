# Gap G3: what effort an unpinned Haiku 5.5 subagent runs at on Claude Code 2.1.293

Method: static read of the 2.1.293 and 2.1.284 binaries with Python mmap (never executed), plus the fleet's
settings files and `~/.zshrc`. Nothing below was measured on a live request. Byte offsets are into
`~/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (236,330,608 bytes, measured by `len(mmap)`).

## Answer

**It depends on how the lead session got its effort, and on this fleet the lead's rung wins.**

One statement for the role-by-effort table:

> On 2.1.293 a subagent's effort resolves in this order: (1) `CLAUDE_CODE_EFFORT_LEVEL` env, (2) a per-agent pin
> (Agent tool `effort` parameter, else agent frontmatter `effort`, else an inherited effort layer), (3) the lead's
> session effort, (4) the model default. Step 3 has two cases. If the lead session holds an explicit level
> (launched with `--effort X`, or set with `/effort`), that level applies to **every** model, including a
> `model: "haiku"` subagent. If the lead session holds no explicit level, step 3 is the settings table looked up
> **for the subagent's own model**, and for `claude-haiku-5-5` the fleet's table returns nothing, so step 4 gives
> `medium`.

Applied to this fleet:

| How the lead was started | Lead session effort state | Unpinned `model: "haiku"` subagent on 2.1.293 |
|---|---|---|
| `claude` wrapper (`~/.zshrc:86`, `:179`, `:181`) | explicit level `max` | **`max`** |
| `claude-x` (`~/.zshrc:197`) | explicit level `xhigh` | **`xhigh`** |
| `claude-h` (`~/.zshrc:198`), `claude-next` (`~/.zshrc:501-508`) | explicit level `high` | **`high`** |
| Any session after `/effort <level>` | explicit level | that level |
| Bare binary, IDE, or headless run with no `--effort` and no `/effort` | `inherit` | **`medium`** (model default) |

Haiku 5.5 is not clamped at `xhigh` or `max`: the baked catalog gives it `max_effort` and `xhigh_effort`.

So the vendor page's "`medium` is the default ... in Claude Code" (pack/effort.md:342 in the brief's numbering; the
sentence is in the "Recommended effort levels for Claude Haiku 5.5" paragraph) is true only for a session that has no
explicit effort. Every fleet launcher passes `--effort`, so the vendor default is never reached by an unpinned spawn.

Two corrections to the brief's framing:

- The stable launcher's default is `max`, not `high` or `xhigh` (`~/.zshrc:86`:
  `CLAUDE_DEFAULT_EFFORT="${CLAUDE_DEFAULT_EFFORT:-max}"`). The worst case for the retrieval slot is `max`.
- The settings table does not reach Haiku 5.5 on this fleet in either direction. It is consulted only in the
  `inherit` case, and there it returns undefined for `claude-haiku-5-5` (details in Evidence 4).

On 2.1.284 none of this applies to the retrieval slot: `haiku` resolves to `claude-haiku-4-5`, which the client
hard-codes as not supporting effort, so no effort is sent. The upgrade plus the alias move is what turns the
inherited rung into a live quota cost.

## Evidence

### 1. The subagent call site (2.1.293, byte 199939922 to 199940900)

```js
function y5n(e){let t=nt();return ly(t,e&&lc(e,t))}
function Gpn({agentDefinition:e,isFork:t,model:r,effortState:n,inheritedLayers:s,recordedBudgetText:m}){
  let l=y5n(n),i=lc(n,r),
  d={agentDefinition:e,...,sessionEffort:l,subagentEffort:ly(r,i,e.effort??Mh(s))}; ...
```

- `n` is the lead's app state: the Agent tool calls `Gpn({agentDefinition:s,isFork:Y,model:ee,effortState:e.getAppState(),inheritedLayers:e.permissionLayers,...})` (byte 199992334).
- `r` is the subagent's resolved model. `i=lc(n,r)` is the lead's session effort resolved **for the subagent's model**.
- `e.effort` is the per-agent pin. The Agent tool copies its `effort` parameter onto the definition just before:
  `{prompt:it,description:ut,cwd:Ke,effort:Lt}=n` (byte 199980844) and
  `We=Y?void 0:Lt;if(We!==void 0)s={...s,effort:We}` (byte 199992306). So the parameter beats frontmatter.
- `Mh(s)` returns the last `kind==="effort"` entry of the inherited permission layers (byte 187937283).

### 2. The precedence function (byte 187913458)

```js
function Vw(e,n,{turnEffort:r,hookEffortValue:s,carriedEffort:d=A(e)}={}){if(!QE(e))return; ...
  let p=WN();if(p===null&&!l)return;
  let S=KOn(e,d),m=p??(p===null?S:void 0)??r??n??S; ... return B(m,e)}
function hT(e,n,r){let s=Vw(e,n,{turnEffort:r})??"high";return N1(s)}
function ly(e,n,r){return QE(e)?hT(e,n,r):void 0}
```

`m = env ?? per-agent effort (r) ?? session effort (n) ?? model default (S)`. `WN()` reads
`CLAUDE_CODE_EFFORT_LEVEL` (byte 187909802). `B` clamps `max` and `xhigh` to `high` only on models that lack them.

### 3. Session effort: explicit level beats everything model-specific (byte 187913002)

```js
function lc(e,n,{withHold:r=!0}={}){let s=e.sessionEffort??re;switch(s.kind){
  case"level":return s.value;
  case"default":return;
  case"inherit":{if(e.settingsEffortTable===void 0)return;
    if(we(e.settingsEffortTable)&&!q())return e.settingsEffortTable.default;
    let d=n??e.mainLoopModelForSession??e.mainLoopModel??$l();
    return r&&_Ct(d)!==void 0?void 0:fe(e.settingsEffortTable,d)}}}
```

- `case "level"` ignores the model argument. A lead holding a level hands that level to any subagent model.
- The launch flag produces a level: `function Frt(e){let n={sessionEffort:_e(Mpr(e)),settingsEffortTable:se()};...}`
  (byte 187914609), called as `...Frt(o.effort)` at startup (bytes 202029586, 202149258);
  `_e(e)` returns `{kind:"inherit"}` when the flag is absent, else `{kind:"level",value:e}` (byte 187909900 region).
  The model and effort pickers also write `sessionEffort:g7(...)` (bytes 206142281, 215349946, 225429169).
- Every fleet launcher passes the flag: `~/.zshrc:179` and `:181` (`--effort "${CLAUDE_DEFAULT_EFFORT:-max}"`),
  `:197`, `:198`, `:504`, `:508`.

### 4. The settings table, and why it returns nothing for Haiku 5.5 here (byte 187910700 to 187912700)

```js
function fe(e,n){let r=Bq(n);if(Object.hasOwn(e.byModel,r))return e.byModel[r];
  if(e.default!==void 0||e.legacyUserEffort===void 0)return e.default;
  return Noo(r)?e.legacyUserEffort:void 0}
function Noo(e){... n=Me.has(e)||!z6(dp(e)) ...}
var Me=new Set(["claude-3-5-haiku",...,"claude-haiku-4-5",...,"claude-mythos-5-1"])   // no claude-haiku-5-5
```

In `se()` a user-settings top-level `effortLevel` becomes `legacyUserEffort` only (`if(E==="userSettings"){s=eVe(v.effortLevel),l.push({source:E,setsTopLevel:!1,...});continue}`); a top-level `effortLevel` from project, local, flag
or policy settings becomes `default` and applies to all models.

Fleet state (measured: Python `json.load` over the files):

- All five `~/.claude*/settings.json`: `effortLevel: "high"`, `modelSettings: {"claude-opus-5-5": {"effortLevel": "high"}}`.
- Worktree `.claude/settings.json` and `.claude/settings.local.json`, and `/Users/chrisren/Development/.claude/settings.local.json`: no `effortLevel`, no `modelSettings`.

So for `claude-haiku-5-5`: no `byModel` entry; `default` is undefined; `legacyUserEffort` is `high` but
`claude-haiku-5-5` is not in the legacy set `Me` and parses as a clean id, so `Noo` is false and `fe` returns
undefined. This matches model-config.yaml:267-269 ("top-level user `effortLevel` is IGNORED for 5.5 ids").
`~/.zshrc:82`'s comment that non-wrapped surfaces fall to `"effortLevel": "xhigh"` is stale for 5.5-generation ids
(and the files now say `high`).

Three settings would change the `inherit` case: a `modelSettings["claude-haiku-5-5"].effortLevel` entry in any
settings file, or a top-level `effortLevel` in project, local, flag or policy settings. None of them affects a lead
that holds an explicit level.

### 5. Model default and capability (byte 184392111)

```js
{id:"claude-haiku-5-5",...,capabilities:["effort","max_effort","xhigh_effort","adaptive_thinking",...,"per_turn_effort",...],default_effort:"medium",advisor_rank:4}
function KOn(e,n){let r=J(e);return(r===void 0?n:void 0)??ZMe(e)??r??Re(e)??Ve(e)}
function Ve(e){return Qa(Be(e))?.default_effort??"high"}
```

Baked default `medium`, agreeing with the vendor page. Ahead of it sit a server flag (`tengu_witty_wand`, per-model),
an org-configured `default_effort_level`, and the served catalog's `default_effort`. `QE` (byte 187905016) returns
false for `claude-haiku-4-5` by hard-coded id and true for ids carrying the `effort` capability.

### 6. Agent tool schema and the built-in Explore agent

- Schema (byte 199976800): `effort:W(Dc).optional().describe("Reasoning effort for this agent. Set this ONLY when the user, or instructions such as CLAUDE.md or a skill, explicitly ask that this agent or delegated work run at a specific effort level, never on your own judgment; otherwise omit it and the agent runs at its usual effort." ...)`.
  The lead is told not to set it on its own, so a pin must come from a written rule, a skill, or frontmatter.
- Explore (byte 192341917): `{agentType:"Explore",...,model:"inherit",omitClaudeMd:!0,...}`. No `effort` field.
- Changelog: pack/cc-changelog.md line 65, "Added an `effort` parameter to the Agent tool".
- The fleet has no agent definition with `effort:` or `model:` frontmatter (measured: `grep -rnE "^(effort|model):"`
  over the worktree's `.claude/agents` and `~/.claude/agents`, 0 hits).

### 7. An unannounced step-down hook (byte 199940380)

```js
if(e.effort!==void 0||WN()!==void 0||d.subagentEffort===void 0||d.subagentEffort==="low")return y;
let g=dZn("tengu_harmonic_riddle",a.CLAUDE_CODE_HARMONIC_RIDDLE,l), h=typeof g==="string"?m7(g):
  typeof g==="number"&&Number.isInteger(g)&&g<0&&l!==void 0?Dc[Math.max(0,Dc.indexOf(l)+g)]:void 0, c=h&&ly(r,i,h);
return c!==void 0&&Dc.indexOf(c)<Dc.indexOf(d.subagentEffort)?{...y,agentDefinition:{...e,effort:c},subagentEffort:c}:y
```

For an unpinned subagent only, a server flag or the env var `CLAUDE_CODE_HARMONIC_RIDDLE` can lower (never raise)
the subagent's effort, either to a named level or by a negative step relative to the lead's level. It can be an
object keyed by the lead's level (`dZn` then `Wje`, byte 194073524). No changelog line mentions it. Its served
value on our accounts is unknown, so the table above is the upper bound if this flag is on.

### 8. 2.1.284 comparison (measured: mmap `find` counts)

`subagentEffort:` 0 hits, `Reasoning effort for this agent` 0 hits, `"claude-haiku-5-5"` 0 hits,
`tengu_harmonic_riddle` 0 hits. The 284 Agent tool has no effort field, and `haiku` cannot resolve to a model that
accepts effort. The latch string "rejected output_config.effort" is present (4 hits), as model-config.yaml:439-441 records.

### Which notes were right

- notes/bin293-probes.md lines 217-228: correct on precedence and on the consequence. Its phrase "under `inherit`
  it is the settings table: `modelSettings[<model>].effortLevel`, else top-level `effortLevel`" needs the
  qualifier that a user-level top-level `effortLevel` does not apply to `claude-haiku-5-5`.
- notes/census-haiku.md lines 274-283: correct that the inherited path changes behavior with no edit; it left the
  point unmeasured. The static read confirms it.
- notes/cc293-axis1.md line 85 ("no longer safe to assume"): correct direction; the order is now derived.
- notes/cc293-axis3.md line 143 ("Non-issue stands"): wrong for the Haiku 5.5 retrieval slot. Lines 11 and 199 of
  the changelog are unrelated to subagent inheritance.

## What remains unknown

- **NOT STATED in any source: the effort value actually sent on the wire for a `model: "haiku"` spawn.** Everything
  above is a static read. Settle it with one capture on 2.1.293: from a lead launched with `--effort xhigh`, spawn
  Explore with `model: "haiku"` and no `effort`, and read `output_config.effort` in the request body (the method
  model-config.yaml:266 used), or the model-and-effort column in `/tasks`. Repeat with a lead launched with no
  `--effort`, and once with `effort: "low"` on the spawn. Three captures close this.
- The served value of `tengu_harmonic_riddle` on Max-plan accounts (Evidence 7). The same capture answers it: a
  result lower than the lead's rung with no pin means the flag is on.
- Whether the served model catalog or the `tengu_witty_wand` flag overrides the baked `medium` default, or the
  baked `effort`, `xhigh_effort` and `max_effort` capabilities, for our accounts. `QE`, `Yte` and `Hrt` consult
  served lookups before the baked list.
- The Workflow `agent({effort})` path and the `--agent` path were not re-read for 2.1.293; model-config.yaml:270-271
  describes them for 2.1.284 only.
- Forks: the schema says a fork "runs at your own effort" and the call site drops the `effort` parameter for forks.
  Not relevant to `model: "haiku"` spawns, since forks inherit the parent model.
