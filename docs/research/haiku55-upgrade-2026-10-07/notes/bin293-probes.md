# Binary probes: Claude Code 2.1.284 (OLD) versus 2.1.293 (NEW)

Date: 2026-10-07. Read-only probe; neither binary was executed.

- OLD: `/Users/chrisren/.claude-284/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (226,563,088 bytes, `VERSION:"2.1.284"`, `BUILD_TIME:"2026-09-28T02:26:10Z"`)
- NEW: `/Users/chrisren/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (236,330,608 bytes, `VERSION:"2.1.293"`, `BUILD_TIME:"2026-10-07T06:36:42Z"`)

Method: Python `mmap.find` / `re.finditer` over each file, restricted to the plain-JS region (byte offset above 150,000,000) to skip the bytecode string tables. Every hit count below is measured that way. Snippets are trimmed minified code; identifiers such as `sQe` or `Gpn` are minifier names and differ between builds. `@N` is the byte offset in the named binary.

Confidence scale: **read directly** (the literal answer is in the quoted code), **inferred from minified code** (answer needs a chain of minified helpers, some not fully traced), **not found**.

Server-side flag values (GrowthBook `tengu_*`) are not in the binary. Where an answer depends on one, only the client fallback default is stated.

---

## 1. Per-agent token budget

**Answer.** NEW adds an optional per-subagent token budget whose value comes from the server flag `tengu_rippling_tulip` or the env var `CLAUDE_CODE_RIPPLING_TULIP`; the client fallback is `null`, so with no flag and no env var there is no per-agent budget. It is advisory only: the number is told to the parent (one sentence in the Agent tool description) and to the subagent (a `<total_tokens>N tokens left</total_tokens>` countdown that clamps at 0); no code path stops, throws, or truncates when it is exceeded. It is wired to the Agent tool launch and Agent resume paths only; Workflow `agent()` and in-process teammates do not receive it.

**Confidence.** Read directly for the source of the value, the wording, the clamp, and the two call sites. Inferred from minified code for "nothing enforces it" (all 9 code references to `totalTokensReminderBudget` were read and none compares against a limit) and for "Workflow and teammates do not carry it" (their spawn call sites omit the field).

Hit counts (measured, mmap find, JS region): `has a budget of` OLD 0 / NEW 3; `tengu_rippling_tulip` 0 / 2; `tengu_streamed_bumblebee` 0 / 3; `tengu_calm_mochi` 0 / 1; `totalTokensBudget` 0 / 10; `isBudgetOnTopOfStart` 0 / 6. `budget_tokens_remaining`: 0 in both. `task_budget` 5 / 5 and `taskBudget` 19 / 19 (unchanged, see end of section).

What sets it (NEW @194076564):

```js
function sQe(e,n){if(a.CLAUDE_CODE_DISABLE_ATTACHMENTS||a.CLAUDE_CODE_SIMPLE)return;
 let r=bWt();if(r!=="padded-countdown"&&r!=="off")return;
 ...
 let s=n===void 0?dZn("tengu_rippling_tulip",a.CLAUDE_CODE_RIPPLING_TULIP,e):Number(n.findLast(...)...);
 if(typeof s!=="number"||!Number.isSafeInteger(s)||s<=0)return;
 if(r==="off"&&n===void 0)return s;
 return s<E5()?s:void 0}
function SWt(e,n){return n??Qc()?.[e]??$r(e,null)}          // env, then clientData, then GrowthBook with default null
function dZn(e,n,r){let s=SWt(e,n),g=typeof s==="string"?gt(s,!1)??s:s;return ls(g)?Wje(g,r):g}
function Wje(e,n){...if(h===n)return g;if(h===w5&&r===void 0)r=g...}   // w5="*"
```

Reading: the value may be a plain integer or a JSON map keyed by effort level with `*` as wildcard. The key `e` is the **session** effort (`y5n(len())`), not the subagent's. The budget only applies when it is smaller than the session-wide reminder budget `E5()` (default 15,000,000, `bKt=15000000`, overridable by `CLAUDE_CODE_TOTAL_TOKENS_REMINDER_BUDGET`).

Where it is attached (NEW @199939862), the only producer of `totalTokensBudget`:

```js
function Gpn({agentDefinition:e,isFork:t,model:r,effortState:n,inheritedLayers:s,recordedBudgetText:m}){
 let l=y5n(n),i=lc(n,r),d={agentDefinition:e,totalTokensBudget:void 0,isBudgetOnTopOfStart:!1,sessionEffort:l,subagentEffort:ly(r,i,e.effort??Mh(s))};
 if(ua()||Tw(e))return t?void 0:d;            // ua() = coordinator mode: no budget
 if(t&&COe()==="none")return;                 // forks: only when tengu_calm_mochi is "forks" or "all"
 let p=sQe(l,m); ...
 let y={...d,totalTokensBudget:p,isBudgetOnTopOfStart:p!==void 0&&COe()==="all"}; ...
```

Callers of `Gpn(` (measured: 2 call sites plus the definition):

```js
// Agent tool launch, NEW @199992334   (he = remote/cloud agent: skipped)
let ce=he?void 0:Gpn({agentDefinition:s,isFork:Y,model:ee,effortState:e.getAppState(),inheritedLayers:e.permissionLayers,recordedBudgetText:void 0});
// Agent resume, NEW @208409653
V=n?.isObserver||A!==void 0?void 0:Gpn({agentDefinition:b,isFork:_,model:Te,...,recordedBudgetText:_?w1o(C):_e});
```

How the model is told (parent side, NEW @199974625):

```js
var So={none:"Each fresh agent you launch has a budget of {N} tokens, counting the context it starts with.",
 forks:"Each agent you launch has a budget of {N} tokens. For a fork, the budget does not count the context it starts with.",
 all:"Each agent you launch has a budget of {N} tokens. The budget does not count the context the agent starts with: its system prompt, its tools, and your prompt to it."};
function Io(){if(SWt("tengu_streamed_bumblebee",a.CLAUDE_CODE_STREAMED_BUMBLEBEE)!==!0)return null;
 let n=sQe(y5n(len()),void 0);if(n===void 0)return null; ... p.replaceAll("{N}",n.toLocaleString("en-US"))}
```

So the sentence in the Agent tool description additionally needs `tengu_streamed_bumblebee === true` (or `CLAUDE_CODE_STREAMED_BUMBLEBEE`).

How the subagent is told, and the absence of enforcement (NEW @195764183 and @194077171):

```js
function HPr(e,n,r,s,g,h,b){let w=b_t(h);if(w==="off")return[]; ...
 let Y=w==="countdown"?Kf(r,Mf())-G:w==="padded-countdown"?q.remaining(M,G,h??E5()):0;
 return[{type:"total_tokens_reminder",text:wWt(w,Y)}]}
function wWt(e,n){return`<total_tokens>${e==="infinite"?"Infinite":e==="fixed"?QDo:Math.max(0,n)} tokens left</total_tokens>`}
```

`remaining()` in class `vKt` only logs telemetry at 75/50/25/10/0 percent (`JDo=[75,50,25,10,0]`, event `tengu_lapis_anchor_threshold`); it returns the number and nothing reads it as a limit.

Surfaces that do not carry it:

```js
// Workflow agent(), NEW @205384064: no totalTokensReminderBudget in the spawn options
...transcriptSubdir:f?`workflows/${f}`:void 0,spawnedByWorkflowRunId:f,description:qe.label,workflowPhase:qe.phase,override:{agentId:We,agentContext:ae},persistedToolResultFiles:wn,model:ke?.model,...
// In-process teammate runner, NEW @218412316: likewise absent
...model:H,preserveToolUseResults:!0,availableTools:J,allowedTools:N,contentReplacementState:v,stickyBetas:z,isTeammate:!0,teammateContext:M...
```

Those agents fall back to `h??E5()`, the general 15,000,000 padded countdown, which already exists in OLD (`padded-countdown` OLD 14 hits, `tokens left</total_tokens>` 2 / 2).

Related, unchanged between builds: a hidden CLI flag `--task-budget <tokens>` ("API-side task budget in tokens (output_config.task_budget)", beta `task-budgets-2026-03-13`) is present in both; it is an API parameter for the main loop, not a per-agent setting, and a cloud-session table in NEW says `taskBudget:st("no task budget is enforced in a cloud session yet")`.

Side finding in the same function: `Gpn` can also lower a subagent's effort below the session's when flag `tengu_harmonic_riddle` (env `CLAUDE_CODE_HARMONIC_RIDDLE`) is set and neither the agent definition nor `CLAUDE_CODE_EFFORT_LEVEL` fixes an effort. New in NEW (0 hits in OLD).

---

## 2. Haiku alias and small/fast model

**Answer.** In NEW the alias `haiku` resolves to `claude-haiku-5-5` on the first-party API and stays `claude-haiku-4-5` on Bedrock, Vertex, Foundry, Mantle, Anthropic-on-AWS, Anthropic-on-Google-Cloud and gateway; in OLD it is `claude-haiku-4-5` everywhere (first-party id `claude-haiku-4-5-20251001`). The default small/fast model is the same resolver, so on first party it also becomes Haiku 5.5, except four helper calls that NEW pins to Haiku 4.5. Resolution is conditional on provider, on the env overrides `ANTHROPIC_SMALL_FAST_MODEL` / `ANTHROPIC_DEFAULT_HAIKU_MODEL`, and on a server-served model catalog when one is active; no plan check and no feature flag appears in the alias path. NEW carries no minimum-version or unsupported-model text for `claude-haiku-5-5`.

**Confidence.** Read directly (alias table, catalog entry, resolver). Inferred from minified code for "no plan or flag gate" (absence in the traced path). The served-catalog override was seen but its contents are server data.

Hit counts (measured): `claude-haiku-5-5` OLD 0 / NEW 11 in the JS region (21 whole-file); `Haiku 5.5` 0 / 2; `smallFastModel` 0 / 0 in both.

Alias table:

```js
// OLD @178331605
haiku:{default:"claude-haiku-4-5"} ... latest_per_family:{fable:"claude-fable-5-1",opus:"claude-opus-5-5",sonnet:"claude-sonnet-5-5",haiku:"claude-haiku-4-5"}
// NEW @184407645
haiku:{default:"claude-haiku-5-5",per_provider:{bedrock:"claude-haiku-4-5",vertex:"claude-haiku-4-5",foundry:"claude-haiku-4-5",mantle:"claude-haiku-4-5",anthropic_aws:"claude-haiku-4-5",anthropic_google_cloud:"claude-haiku-4-5",gateway:"claude-haiku-4-5"}}
... latest_per_family:{...,haiku:"claude-haiku-5-5"}
```

Catalog entry (NEW @184392107, absent from OLD):

```js
{id:"claude-haiku-5-5",family:"haiku",display_name:"Haiku 5.5",knowledge_cutoff:"June 2026",
 provider_ids:{first_party:"claude-haiku-5-5",bedrock:"us.anthropic.claude-haiku-5-5",vertex:"claude-haiku-5-5",...},
 fallback_3p:"claude-haiku-4-5",context:{window:1e6,native_1m:!0,supports_1m_beta:!0},
 max_output_tokens:{default:128000,upper:128000},pricing:"haiku_55",
 capabilities:["effort","max_effort","xhigh_effort","adaptive_thinking","mid_conv_tool_change","context_management","rejects_disabled_thinking","per_turn_effort","lean_prompt","org_locked_thinking","haiku_5_5_early_stopping_guidance"],
 default_effort:"medium",advisor_rank:4}
```

For comparison, Haiku 4.5 in both builds: `context:{window:200000,supports_1m_suffix:!0},max_output_tokens:{default:32000,upper:64000},pricing:"haiku_45",capabilities:["context_management"],advisor_rank:1`.

Resolver (NEW @186758412 and @186749525; OLD is structurally identical at @180087586 and @180079291):

```js
function f6(){let e=a.ANTHROPIC_DEFAULT_HAIKU_MODEL;if(e!==void 0)return cA(e);return ga("haiku")??ic()}
function ic(e=VS()){return pa("haiku",e)??e.haiku45}
function iN(e,n,r){if(r!=="firstParty"||e!=="opus"&&e!=="sonnet"&&e!=="haiku")return;let s=Ob(e);...}   // ga(): served-catalog override, first party only
function xKe(e,t){let r=j6().aliases,n=...;let l=n.per_provider;return(l&&Object.hasOwn(l,t)?l[t]:void 0)??n.default}

function Yw(){let e=a.ANTHROPIC_SMALL_FAST_MODEL;if(e!==void 0)return Yb(cA(e));
 if(!fst()){ ...bedrock/vertex special case...; return nt()}          // no haiku configured: use the main model
 return a.ANTHROPIC_DEFAULT_HAIKU_MODEL!==void 0?Yb(f6()):tv(f6())}
function tv(e){return lc(e)?nt():e}                                    // deniedModels: fall back to main model
```

Order: `ANTHROPIC_SMALL_FAST_MODEL` (small/fast only), then `ANTHROPIC_DEFAULT_HAIKU_MODEL`, then served catalog (first party), then the baked alias table by provider, then `haiku45`. Setting `ANTHROPIC_DEFAULT_HAIKU_MODEL=claude-haiku-4-5` therefore pins the alias back on NEW.

New in NEW, a pinned-to-4.5 helper (no equivalent function in OLD):

```js
function mst(){if(Pe()==="firstParty"&&BMn()){let e=VS().haiku45;if(!lc(e))return e}return Yw()}
```

Its 4 call sites (measured): quota probe (`Iu.probeQuotaStatus(mst(),e,n)`), API key verification (`source:"verify_api_key"`), the rewind-limit question, and spinner-tip selection. Everything else that asks for the small/fast model goes through `Yw()` and so moves to Haiku 5.5 on first party.

Minimum-version text: `requires Claude Code v`, `not supported by this version`, `model_min_cli`: 0 hits in both. The `min_version` / `minVersion` hits in NEW (12 / 17) were read and all belong to Remote Control (`tengu_bridge_min_version`, default `"2.1.270"`) and host-interface versioning, none to a model.

OLD and the raw id: OLD contains zero occurrences of `claude-haiku-5-5`, so it has no catalog row, no capabilities, no pricing key, and no alias for it. How OLD treats the raw id if passed explicitly was not traced.

Two smaller Haiku 5.5 differences in NEW:

```js
// system prompt section gated on the capability, flag default true (NEW @194093455)
function xLo(e,n){if(!BN("haiku_5_5_early_stopping_guidance",e,n))return null;return $r("tengu_idempotent_wolf",!0)?CLo:null}
// CLo begins: "The reasoning effort setting changes how much you think before you act. It does not change how much of the request you are expected to finish. ..."

// auto mode on third-party providers: Haiku 5.5 is allowed where other Haiku models are not
// OLD @180126499
if(kmn()&&(n==="claude-opus-4-6"||n==="claude-sonnet-4-6"||n.includes("haiku")))return!1;
// NEW @186798459
if(iDn()&&(n==="claude-opus-4-6"||n==="claude-sonnet-4-6"||n.includes("haiku")&&n!=="claude-haiku-5-5"))return!1;
```

---

## 3. Effort and thinking for Haiku 5.5

**Answer.** NEW accepts all five levels for `claude-haiku-5-5` (`low`, `medium`, `high`, `xhigh`, `max`), its catalog default effort is `medium`, and thinking is adaptive (`type:"adaptive"`, no `budget_tokens`) and cannot be turned off. Haiku 4.5 is treated as a different class in both builds: no effort parameter at all, no adaptive thinking (classic `enabled` thinking), and thinking can be disabled. A subagent does not automatically get the model default: it inherits the session's effort unless the agent definition, the new Agent tool `effort` parameter, or `CLAUDE_CODE_EFFORT_LEVEL` says otherwise.

**Confidence.** Read directly for the level list, capability flags, the hard-coded Haiku 4.5 exclusions and the default. Inferred from minified code for the precedence chain. `between_tools`: 0 hits in NEW; the 12 OLD hits are an unrelated telemetry name (`tengu_dir_sync_between_tools_publish`), so no interleaved-thinking setting by that name exists in either.

```js
// NEW @184643288
var Dc=["low","medium","high","xhigh","max"]

// NEW @187905113: effort support. Haiku 4.5 is excluded by name; Haiku 5.5 passes via its "effort" capability
function QE(e){... if(r.includes("claude-3-")||r==="claude-opus-4-0"||r==="claude-opus-4-1"||r==="claude-sonnet-4-0"||r==="claude-sonnet-4-5"||r==="claude-haiku-4-5")return!1;
 if(a.CLAUDE_CODE_ALWAYS_ENABLE_EFFORT)return!0;if(Zy(r,"effort",e)||r==="claude-mythos-5")return!0;return k2(Mc(e))}
function Yte(e){... "max_effort" ... r==="claude-haiku-4-5")return!1;if(Zy(r,"max_effort",e)||...)return!0;...}
function Hrt(e){... "xhigh_effort" ... r==="claude-haiku-4-5")return!1;if(Zy(r,"xhigh_effort",e)||...)return!0;...}
function B(e,n){let r=e;...if(r==="max"&&!Yte(n))r="high";if(r==="xhigh"&&!Hrt(n))r="high";return r}   // clamp for models lacking the level
function ly(e,n,r){return QE(e)?hT(e,n,r):void 0}                                                      // Haiku 4.5: effort is undefined
```

Thinking (NEW @186794300 to @186795544):

```js
function vTt({runtimeOverride:e,resolvedModel:n,canonicalModel:r}){if(e!==void 0)return e;
 let s=a.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING&&(r.includes("opus-4-6")||r.includes("sonnet-4-6"));
 return wco(n)&&!s?"adaptive":"enabled"}
function wco(e){... ||r==="claude-haiku-4-5")return!1;let s=Zy(r,"adaptive_thinking",e);if(s!==void 0)return s;...}
function iAe(e){... ||n==="claude-haiku-4-5")return!1;let r=Zy(n,"rejects_disabled_thinking",e);if(r!==void 0)return r;...}
function iYt(e){if(!Dv(e))return;return`Thinking can't be turned off for ${...}`}
function Aye(e){if(iAe(e))return[void 0,2048];return[!1,0]}
```

Default effort (NEW @187914300 onward):

```js
function KOn(e,n){let r=J(e);return(r===void 0?n:void 0)??ZMe(e)??r??Re(e)??Ve(e)}
// J  = per-model map in server flag tengu_witty_wand
// ZMe = org-configured default_effort_level (first party)
// Re = served-catalog default_effort
function Ve(e){return Qa(Be(e))?.default_effort??"high"}      // baked catalog: "medium" for claude-haiku-5-5
```

Precedence for what a (sub)agent actually runs at (NEW @187910400 onward):

```js
function Vw(e,n,{turnEffort:r,hookEffortValue:s,carriedEffort:d=A(e)}={}){if(!QE(e))return; ...
 let p=WN();                     // CLAUDE_CODE_EFFORT_LEVEL
 let S=KOn(e,d),m=p??(p===null?S:void 0)??r??n??S; ... return B(m,e)}
function lc(e,n,...){let s=e.sessionEffort??re;switch(s.kind){case"level":return s.value;case"default":return;case"inherit":{... return ... fe(e.settingsEffortTable,d)}}}
```

Reading: env `CLAUDE_CODE_EFFORT_LEVEL`, then the per-agent effort `r` (agent frontmatter `effort`, or the Agent tool `effort` parameter), then the session effort `n` (an explicit session level applies to every model; under `inherit` it is the settings table: `modelSettings[<model>].effortLevel`, else top-level `effortLevel`), then the model default. Consequence for routing: a Haiku 5.5 subagent spawned from a session running at `xhigh` runs at `xhigh` unless one of the higher-precedence settings pins it, and Haiku 5.5 will not be clamped because it supports `xhigh` and `max`.

Other models' baked defaults in NEW for reference: Sonnet 5.5 `medium`, Opus 5.5 `medium`, Fable 5.1 `high`.

---

## 4. Built-in agents

**Answer.** No change. In both builds Explore is `model:"inherit"` with an inherit cap of `opus` on first party (a parent above Opus is stepped down to Opus), Plan is `model:"inherit"`, and general-purpose declares no model, so it takes the default subagent model (the parent's, unless `CLAUDE_CODE_SUBAGENT_MODEL` is set). The only built-in pinned to `haiku` is `claude-code-guide`, which therefore moves to Haiku 5.5 on first party in NEW; `statusline-setup` is `sonnet` in both.

**Confidence.** Read directly.

```js
// NEW @192341917 (OLD @184987346 is identical apart from minified names)
Xv={agentType:"Explore",whenToUse:gBn,whenToUseLean:hBn,disallowedTools:[...],source:"built-in",baseDir:"built-in",model:"inherit",omitClaudeMd:!0,getSystemPrompt:()=>mBn()};
function wfe(e,n){if(e.agentType!==Xv.agentType||e.source!=="built-in")return e.model;
 if(rJt())return"inherit";                                   // rJt(): Pe()!=="firstParty"
 if(a.CLAUDE_CODE_DISABLE_EXPLORE_INHERIT_CAP)return"inherit";
 return yBn(n)?{inheritCap:Qat}:"inherit"}var Qat="opus";

// NEW @192345041
tJ={agentType:"Plan",...,source:"built-in",tools:Xv.tools,baseDir:"built-in",model:"inherit",omitClaudeMd:!0,...};
// NEW @194165994
JB={agentType:"general-purpose",whenToUse:"...",tools:["*"],source:"built-in",baseDir:"built-in",getSystemPrompt:FNo};
// NEW @194163163 (claude-code-guide; OLD @186274655 same)
source:"built-in",baseDir:"built-in",model:"haiku",permissionMode:"dontAsk",
// NEW @194179864
AVt={agentType:"statusline-setup",...,model:"sonnet",color:"orange",...};
```

`model:"haiku"` occurrences in agent definitions (measured): 1 in each build. Explore does not use Haiku by default in either build; a fleet that wants Haiku retrieval must keep passing `model: "haiku"` (or a custom agent definition) explicitly.

---

## 5. Spawn depth

**Answer.** The comparison is inclusive (`>=`) and the default is 3 in both builds; nothing changed in the limit or the check. The only difference is that NEW also consults cached client data for `tengu_hazel_trellis` before GrowthBook.

**Confidence.** Read directly.

```js
// OLD @184451870
var o=3,_="tengu_hazel_trellis";function PE(){let n=a.CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH;if(n!==void 0)return n;
 ... e=r(_,o);t.maxSubagentSpawnDepthFromGrowthBook=typeof e==="number"&&Number.isInteger(e)&&e>=1?e:o ...}
// NEW @191927524
var n=3;var _="tengu_hazel_trellis";function Uw(){let e=a.CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH;if(e!==void 0)return e;
 ... o=S()?.[_],r=u(o)?o:A(_,n);t.maxSubagentSpawnDepthFromGrowthBook=u(r)?r:n ...}

// OLD @192020481
Tt=Pd(e.agentContext),kt=PE();if(Tt>=kt)throw ... new q(`Subagent nesting limit reached (depth ${Tt} of ${kt}). ...`)
// NEW @199981324
zt=Fu(e.agentContext),Wt=Uw();if(zt>=Wt)throw ... new F(`Subagent nesting limit reached (depth ${zt} of ${Wt}). Complete this task directly using your tools instead of spawning another agent. If the user explicitly requested deeper nesting, ask them to raise CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH.`)
```

The compared value is the spawner's own depth (the child is logged as `agent_depth: Fu(e.agentContext)+1`), so with the default an agent at depth 0, 1 or 2 may spawn and an agent at depth 3 may not.

---

## 6. Background Bash cap

**Answer.** NEW adds a deadline on backgrounded Bash commands that applies only to headless sessions: default 30 minutes, or 10 minutes for a single-shot print session, with a ceiling of 2 hours (higher if `BASH_MAX_TIMEOUT_MS` is larger); the Bash `timeout` parameter sets it per command when `run_in_background` is used. Interactive terminal sessions are exempt, as are desktop-app-hosted and VS Code-hosted sessions and one server mode that calls `disableBackgroundDeadline()`. OLD has no such deadline.

**Confidence.** Read directly for the constants, the gate and the kill path. Inferred from minified code for the mapping to session kinds: the predicate is "not interactive", which covers `-p` and SDK sessions; cloud sessions were not individually traced and are covered only insofar as they run non-interactive and are not one of the excluded entrypoints.

Hit counts (measured): `backgroundDeadlineDisabled` OLD 0 / NEW 2; `tengu_cosmic_shore` 0 / 1; `may run in the background before it is stopped` 0 / 1.

```js
// NEW @190461424 (timeout module)
var a=120000,i=600000; ... var s=1800000;
function Tae(){return Math.min(Math.max(7200000,gke()),2147483647)}     // max: 2 h or BASH_MAX_TIMEOUT_MS
function xts(n){return Math.max(s,cte(n))}                               // 30 min or BASH_DEFAULT_TIMEOUT_MS

// NEW @191288733 (the condition)
function WCn(){return uz()&&!ok().backgroundDeadlineDisabled}
function e7r(){return WCn()&&C("tengu_cosmic_shore",!0)}                 // flag, client default true
var uoe=600000;function OVt(){return JJ()?Math.max(uoe,cte()):xts()}     // JJ() = singleShotPrintSession: 10 min
function wir(e){return e7r()?t7r(e):void 0}
function t7r(e){return Math.min(e??OVt(),Tae())}

// NEW @184518574 (session kind)
function uz(e=Ee()){let t=Ep()&&!n().claudecode;return e&&!t&&!Ev()}
function Ee(){return!n().host.launchOptions.isInteractive()}             // @184042131
function Ep(){return p()&&!n().childSession}                             // p(): entrypoint in {"claude-desktop","claude-desktop-3p","local-agent"}
function Ev(){let e=n();return e.entrypoint==="claude-vscode"&&!e.childSession&&!e.claudecode}
```

`uz()` is passed elsewhere as `Yin({headless:uz()})`, which confirms its meaning. Enforcement is real (NEW @196310916):

```js
function H0r(e,n,r){try{if(!e7r())return;let s=e.taskRegistry.get(e.taskId);
 if(!op(s)||s.status!=="running"||s.notified||s.shellCommand?.status!=="backgrounded")return;
 r.cause="deadline",FTn(e,"deadline"), ... t(`LocalShellTask ${e.taskId}: stopped at its ${n}ms background deadline`)}...}
... q=wir(b),Y=q===void 0?void 0:setTimeout(H0r,q,w,q,G) ...
```

Model-facing text added to the Bash tool in headless sessions: "With `run_in_background` the timeout is instead how long the command may run in the background (default ...ms / ... minutes, max ...ms / ... hours); at that limit it is stopped and you are notified."

Opt-out seen in code: `M.disableBackgroundAgentLaunch(),M.disableRemoteAgentIsolation(),M.disableBackgroundDeadline()` at NEW @227269654, inside a server entry that registers `name:"claude/tengu"`; which CLI mode that is was not traced. No env var that disables the deadline was found; `BASH_DEFAULT_TIMEOUT_MS` above 30 minutes raises the default and `BASH_MAX_TIMEOUT_MS` above 2 hours raises the ceiling.

---

## 7. Agent tool `model` parameter

**Answer.** The enum is identical in both builds: `sonnet`, `opus`, `haiku`, `fable`. NEW adds a sibling `effort` parameter (`low`, `medium`, `high`, `xhigh`, `max`) that OLD does not have.

**Confidence.** Read directly.

```js
// OLD @192015674
model:z(["sonnet","opus","haiku","fable"]).optional().describe(`Optional model override for this agent. Takes precedence over the agent definition's model frontmatter and the configured default subagent model. ...`),
run_in_background:O().optional()...
// NEW @199975991
model:W(["sonnet","opus","haiku","fable"]).optional().describe(`Optional model override for this agent. ...`),
effort:W(Dc).optional().describe("Reasoning effort for this agent. Set this ONLY when the user, or instructions such as CLAUDE.md or a skill, explicitly ask that this agent or delegated work run at a specific effort level, never on your own judgment; otherwise omit it and the agent runs at its usual effort."+(ZZ()?' Ignored for subagent_type: "fork": a fork runs at your own effort.':"")),
run_in_background:H().optional()...

// NEW @199979156: when each parameter is removed from the schema
h=a.CLAUDE_CODE_SUBAGENT_MODEL_FORCE?p.omit({model:!0}):p;return WN()!==void 0?h.omit({effort:!0}):h
```

So `effort` disappears from the tool when `CLAUDE_CODE_EFFORT_LEVEL` is set, and `model` disappears when `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` is set. There is no way to name a specific Haiku version through this parameter: `haiku` goes through the alias in section 2.

---

## 8. Auto-mode classifier model

**Answer.** Neither build uses Haiku for the auto-mode permission classifier. Both resolve it as: a server-configured model (`tengu_auto_mode_config.modelByMainModel` or `.model`) if present, otherwise Sonnet 5 (`claude-sonnet-5`, or a valid `ANTHROPIC_DEFAULT_SONNET_MODEL`), otherwise the main model itself (Opus 5 family when the main model is Fable or Mythos). The difference is at the edges: OLD skipped the Sonnet 5 default when the main model was any Haiku, so a Haiku-led session classified with Haiku itself, while NEW removes that exclusion, so a Haiku-led session classifies with Sonnet 5; NEW also refuses `ANTHROPIC_DEFAULT_SONNET_MODEL` set to Sonnet 5.5 or Opus 5.5 as the classifier.

**Confidence.** Read directly for the resolver and both default functions. The server-configured value is not in the binary, so the model actually used in production is not stated. `CLAUDE_CODE_AUTO_MODE_MODEL` and `CLAUDE_CODE_BG_CLASSIFIER_MODEL` appear only in env allow-lists (3 hits each in both builds, no reader), so they do not appear to select the model in these builds. `yolo`-named classifier symbols: 0 hits in the JS region of both.

```js
// NEW @193239021 (OLD QDe @187485036 is the same shape)
function b2e(){let e=nt(),n=OS(),r=xIt(n?.modelByMainModel,{vet:(s)=>HNe(s,"modelByMainModel")})??HNe(n?.model,"model");
 if(r)return{value:r,src:"gb"};
 if(Mk().externalSonnet5Probe!=="demoted"){let s=sco(e);if(s)return{value:s,src:"default",externalDefault:!0}}
 return{value:lFe(e),src:"default"}}

// OLD @180084705
function Hx(e){let n=$I(e);if(n==="claude-sonnet-4-6"||n==="claude-sonnet-4-5"||n.startsWith("claude-haiku-"))return;
 let r=a.ANTHROPIC_DEFAULT_SONNET_MODEL,g=...;if(g!==void 0&&!(...))return;
 if(g===void 0){let h=yg().sonnet5;if(!Yr(h))return;g=h}return mh(eC(g),e)}

// NEW @186755345
var eN=["claude-sonnet-5-5","claude-opus-5-5"],Xb=!1;
function tN(e){let n=pg(e);if(n==="claude-sonnet-4-6"||n==="claude-sonnet-4-5")return;
 let r=a.ANTHROPIC_DEFAULT_SONNET_MODEL,g=...;
 if(g!==void 0&&eN.includes(pg(cA(g)))){... t(`Auto mode classifier: ANTHROPIC_DEFAULT_SONNET_MODEL=${g} cannot serve as the classifier; using the Sonnet 5 default instead`);g=void 0}
 ...if(g===void 0){let h=VS().sonnet5;if(!Kr(h))return;g=h}return sv(cA(g),e)}

// fallback, both builds
function GMn(e){if(Vle(e)||yhr(e))return ZD(e);return e}     // Fable/Mythos main -> Opus 5 family; otherwise the main model
```

`e=nt()` is the session's main-loop model, so the classifier choice follows the lead model, not the model of the subagent whose tool call is being judged.

---

## Not found or not traced

- Server-side values of every `tengu_*` flag named above (`tengu_rippling_tulip`, `tengu_streamed_bumblebee`, `tengu_calm_mochi`, `tengu_harmonic_riddle`, `tengu_witty_wand`, `tengu_cosmic_shore`, `tengu_idempotent_wolf`, `tengu_auto_mode_config`). A `grep -l` for the two budget flag names across `~/.claude*/.claude.json`, `~/.claude.json` and `~/.claude*/*.json` returned no file, so no locally cached value was seen.
- Whether this account's server-served model catalog is active and whether it remaps `haiku`.
- How OLD (2.1.284) behaves when given the raw id `claude-haiku-5-5`.
- `budget_tokens_remaining`: no occurrence in either build.
- A `smallFastModel` settings key: no occurrence in either build.
- Any per-plan (Max versus API key) condition on the `haiku` alias.
- Which CLI mode owns the `disableBackgroundDeadline()` call, and whether cloud sessions hit the background deadline in practice.
- Per-model token pricing behind the keys `haiku_55` / `haiku_45` (not looked up; cost is not the binding constraint for this decision).
