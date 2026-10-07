# Gap G5: what 2.1.293 changes in the prompt and request for claude-haiku-5-5

Source: read-only Python mmap search of
`~/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (NEW, 236,330,608 bytes) and
`~/.claude-284/.../claude.exe` (OLD, 226,563,088 bytes). Neither binary was executed. Byte offsets
are NEW unless marked OLD. Vendor text is cited by pack file and line. Every "measured" number below
is a string count from that mmap search.

## Answer

1. **Nothing here is new machinery except one prompt section.** `lean_prompt`,
   `mid_conv_tool_change` and `rejects_disabled_thinking` all exist in OLD (10, 10 and 9 hits,
   measured). What 2.1.293 adds is a catalog row that gives Haiku 5.5 those capabilities, where
   Haiku 4.5 has only `context_management`. The one new piece is the
   `haiku_5_5_early_stopping_guidance` section (0 hits in OLD, 4 in NEW).

2. **`lean_prompt`** switches the model to the short ("lean") variant of the default system prompt
   and of the tool descriptions. Haiku 4.5 gets the full variant; Haiku 5.5 gets the lean one. It
   changes prompt size and wording, not behavior rules.

3. **`mid_conv_tool_change`** lets the client send the
   `mid-conversation-tool-changes-2026-07-01` beta for this model, so tools that appear late
   (deferred tools, the advisor tool, inline tool definitions) are announced inside the conversation
   instead of by rewriting the top-level tool list. Off for Haiku 4.5, on for Haiku 5.5.

4. **Yes, small/fast helper calls run with thinking on for Haiku 5.5.** Helper calls ask for
   `thinking: disabled`. For a model flagged `rejects_disabled_thinking` the client does not send
   `{type:"disabled"}`; it omits the `thinking` field. The vendor says thinking is on by default
   when the field is omitted. For Haiku 4.5 the same code sends `{type:"disabled"}`. So every helper
   call that moves to Haiku 5.5 at the flip gains thinking tokens. This is read from code; the token
   cost per call is NOT measured.

5. **Early stopping: partly injected, main thread only. Verify-before-done: not injected.**
   - A Claude Code-authored anti-early-stopping section (five paragraphs, different wording from the
     vendor's two-line text) is added to the default system prompt for Haiku 5.5, behind a flag that
     defaults on.
   - That section is built only in the default (main-thread) system prompt. Subagents get their own
     agent prompt plus a fixed notes block, so an Explore or custom subagent on Haiku 5.5 does not
     receive it.
   - The vendor's verify-your-changes paragraph is absent from the binary (0 hits on four distinct
     phrases). The injected section has two related sentences about setting up the project and
     saying when code cannot be run, but no instruction to run a real check before reporting done.
   - The vendor's search-nudge and JSON-with-tools texts are also absent (0 hits each).

**Consequence for the fleet.** Any Haiku 5.5 subagent role (retrieval, extraction, verifier, judge)
needs the fleet's own completion text if early stopping shows up, and any code-writing Haiku 5.5
worker needs the fleet's own verification paragraph in every case.

## Evidence

### Catalog row (already in notes/bin293-probes.md, re-read at NEW @184392107)

Haiku 5.5 capabilities: `effort, max_effort, xhigh_effort, adaptive_thinking, mid_conv_tool_change,
context_management, rejects_disabled_thinking, per_turn_effort, lean_prompt, org_locked_thinking,
haiku_5_5_early_stopping_guidance`. Haiku 4.5: `context_management` only.

String counts (measured, OLD / NEW): `lean_prompt` 10 / 11, `mid_conv_tool_change` 10 / 12,
`rejects_disabled_thinking` 9 / 10, `org_locked_thinking` 4 / 5, `whenToUseLean` 3 / 3,
`haiku_5_5_early_stopping_guidance` 0 / 4, `tengu_idempotent_wolf` 0 / 2, `lean_body` 0 / 1.

Capability lookup, NEW @184412128. An env override wins, then a server-served capability, then the
baked catalog:

```js
function Zy(e,t,r){return dat(t,e)??eJt(e,t,r)}          // dat(): CLAUDE_CODE_MODEL_CAPABILITIES env
function eJt(e,t,r){if(xF().servedCapabilityLookup?.(t,[r,m(e)])===!0&&S(t))return!0;return Xmo(e,t)?!0:void 0}
function Xmo(e,t){return Qa(m(e))?.capabilities.includes(t)}
```

### lean_prompt (NEW @187980600-187981400)

```js
function Ri(e){let n=Be(e),s=Zy(n,"lean_prompt",e);if(s!==void 0)return!s;
  if(dCe(e)||n==="claude-mythos-5")return!1;
  if(n.includes("claude-3-")||n.includes("haiku")||n.includes("sonnet")||n==="claude-opus-4-0"||...)return!0;
  return!Nd()}
function qo(e){if(!e)return!1;if(Le(a.CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT))return!0;
  if(ps(a.CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT))return!1;if(!Ri(e))return!0; ...}
class Qo{... leanPrompt=bo(qo); ...}      function Hq(e){...n.leanPrompt(e)}   function $P(e){return e.leanPrompt??Hq(e.model)}
```

Reading: with the capability, `Ri` is false and `qo` (lean) is true. Without it, any id containing
"haiku" returns `Ri` true, so Haiku 4.5 is not lean unless `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT` is set.

What lean changes, read at three consumers:

- Default system prompt builder `FKt` (NEW @194119757): `g=Hq(s)`, section keys take an `:L`
  suffix (`communication:L`, `action_caution:L`, `session_guidance:L`, `memory:L`, `focus_mode:L`),
  and a short body is used: `Se=g?[["lean_body",KLo(G,n)]...`. `KLo` (@194114133) is a compact
  "# Harness" block of five bullets.
- Tool descriptions: `Zis` (@188076891) returns a shorter Read tool description when
  `$P({model,leanPrompt})` is true. `$P(` has 17 call sites (measured), so the short variants are
  per-tool and apply to whichever model the request is for, including a Haiku 5.5 subagent.
- Agent list: `ktr(e,n)` (@195670146) uses `e.whenToUseLean||e.whenToUse`. Explore's lean text
  (@192341951) drops the "quick" breadth option and says it "locates code; it doesn't review or
  audit it". This text is shown to the model that calls the Agent tool, so it depends on the
  caller's model, not on the Explore model.

How many tokens lean saves on a Haiku 5.5 request: NOT STATED and not measured.

### mid_conv_tool_change (NEW @185323226, @186797340, @191797558, @194847263)

```js
A_=y("mid_conv_tool_change","mid-conversation-tool-changes-2026-07-01")
function Tye(e){if(!nh()||!B7(e))return!1;if(a.CLAUDE_CODE_FORCE_MID_CONVERSATION_SYSTEM)return!0;
  let n=Be(e);if(yko(n))return!1;let r=Zy(n,"mid_conv_tool_change",e);if(r!==void 0)return r;
  return n==="claude-mythos-5"||Qa(jO(n))===void 0}
// consumers
surfaceLateToolAdditions:n.betas.includes(A_)&&Tye(r),
advisorToolChanges:n.advisorDeferred===!0&&n.advisorModel!==void 0&&n.betas.includes(A_)&&Tye(r),
inlineToolDefinitions:...n.betas.includes(Ky)&&Tye(r)?n.byValueNames:void 0
```

Haiku 4.5 is in the catalog without the capability, so `Tye` is false for it. For Haiku 5.5 it is
true when the mid-conversation system-message path is available (`nh()` and `B7`). `Tye(` has 10
call sites (measured). Whether this saves cache writes on a short Explore run is not measured.

### Thinking on helper calls (NEW @186794300-186795100, @194881300-194883400)

```js
function iAe(e){let n=Be(e);if(n.includes("claude-3-")||...||n==="claude-haiku-4-5")return!1;
  let r=Zy(n,"rejects_disabled_thinking",e);if(r!==void 0)return r;return k2(Mc(e))}
function Aye(e){if(iAe(e))return[void 0,2048];return[!1,0]}       // [thinking, extra max_tokens]

// request builder; r = thinkingConfig
ik=r.type!=="disabled"&&!iS, Jd=()=>Rt.thinking.rejectsDisabled||Ut!==void 0&&iAe(Ut), ... Kc=void 0;
if(ik&&Rt.thinking.supported) ... adaptive / enabled ...
else if(r.type==="disabled"&&Pe()==="firstParty"&&!iS&&Rt.thinking.supported&&!Jd())Kc={type:"disabled"};
...
let eO=Kc?.type==="enabled"||Kc?.type==="adaptive"||Kc===void 0&&Jd()   // "extended thinking is active"
... max_tokens:sk,thinking:Kc,
```

- The shared helper (`sH` to `Zfr`, @194973610-194974700) defaults to
  `thinkingConfig:{type:"disabled",mechanical:!0}`. `mechanical:!0` appears 38 times in NEW
  (measured, 13 in OLD by the `mechanical:!0` string).
- For Haiku 4.5, `iAe` is false, so the request carries `thinking:{type:"disabled"}`.
- For Haiku 5.5, `iAe` is true, `Kc` stays undefined, and the `thinking` key is left out. The
  client itself treats that state as thinking active (`eO`, which demotes a forced `tool_choice` to
  auto).
- Vendor: "Thinking is on by default and counts toward `max_tokens`" (pack/effort.md:344,
  pack/prompting.md:37).
- Side-query callers use `Aye` and add 2,048 tokens of `max_tokens` headroom when thinking cannot be
  disabled: plugin `$.model.complete` (@194412874), memory recall selection (@195696881), auto-mode
  setup (@207120076).
- The main request builder adds no such headroom: `sk=Math.min(maxTokensOverride||maxOutputTokensOverride||default, default)`.
  Three artifact-comment helper calls pass `maxOutputTokensOverride` of 5, 96 and 128
  (@199640881, @199638065, @199553762). With thinking counted toward `max_tokens`, those could be
  cut off on Haiku 5.5. Not measured, and the fleet may never hit those paths.
- OLD has the same logic (`rejectsDisabled||` @OLD 186853134, `[void 0,2048]` @OLD 180123231). The
  change at the flip is only that the helper model becomes one that carries the capability.
- Conflict to note: the vendor says `thinking:{type:"disabled"}` is accepted at low, medium and
  high effort (pack/prompting.md:38, pack/effort.md:346). The client still marks the model
  `rejects_disabled_thinking` and never sends it. `CLAUDE_CODE_MODEL_CAPABILITIES` with a
  `-rejects_disabled_thinking` entry is the override path seen in `Jmo` (@184412128); its effect
  was not tested.
- Scope: `Yw()` has 17 references (measured). Four other helper calls are pinned to Haiku 4.5 via
  `mst()` (notes/bin293-probes.md section 2) and keep thinking off.
- Opt-outs seen in code: `ANTHROPIC_SMALL_FAST_MODEL` or `ANTHROPIC_DEFAULT_HAIKU_MODEL` set to
  `claude-haiku-4-5` keeps helpers on the old model. No `.json` or `.sh` file in the fleet repo sets
  either (measured: `grep -rn` over the worktree, hits only in research docs and one hook library).
  The operator's live settings were not read.

### Early-stopping section (NEW @194090600-194093600, @194121190)

```js
function xLo(e,n){if(!BN("haiku_5_5_early_stopping_guidance",e,n))return null;return $r("tengu_idempotent_wolf",!0)?CLo:null}
// inside FKt, the default system prompt builder
ap("heron_brook",()=>RLo()??xLo(h,s)),
```

- `CLo` is five paragraphs. It opens "The reasoning effort setting changes how much you think
  before you act. It does not change how much of the request you are expected to finish." It
  covers: do not check in because a task is large, end the turn only when done or blocked, ask
  first only when the likely reading cannot be named, working-tree edits are reversible so decide
  open choices yourself, finish everything not blocked and report the stuck part first.
- `RLo()` returns a server-supplied replacement text when one is present, and it wins over `CLo`.
  `tengu_idempotent_wolf` is a remote flag with default true, so the section can be turned off
  server-side.
- Vendor's own text is not in the binary (measured, 0 hits each): "Keep working until everything",
  "only stop to ask when", "Don't add new features, docs, or refactors". So `CLo` covers the
  "keep going" half and not the vendor's "don't add unrequested features" half.
- Subagents do not get it. The subagent path (@199929600 and @199994700) is
  `DWt([agent.getSystemPrompt(...)], model, budget)`, and `DWt` (@194123340) appends only the
  "Messages from the agent that launched you" paragraph, the fixed "Notes:" block and an optional
  token-budget line. It does not call `FKt`. The fallback agent prompt (`k3o`) has one relevant
  sentence: "Complete the task fully—don't gold-plate, but don't leave it half-done."

### Verify-before-done (vendor pack/prompting.md:89-96)

Measured 0 hits in NEW for "run a real check that exercises", "syntax-only check", "before reporting
it done", "type-checked", "exercises the change". The nearest text is inside `CLo`: "Setting up the
project so you can build and test it, such as installing its declared dependencies, is part of the
work. If the code still cannot be built or run here, say so and make the changes you can verify by
reading." That is main thread only and does not tell the model to run a check.

Also absent (0 hits each): the search nudge "Your training data ends well before"
(pack/prompting.md:77-79) and the JSON line "The JSON output format applies to your final answer
only" (pack/prompting.md:~66).

### Changelog

pack/cc-changelog.md lines 3-815 mention Haiku once (line 3: model added, default Haiku on the
Anthropic API). No entry mentions the lean prompt, helper-call thinking, or the early-stopping
section for Haiku (measured: `grep -i -E 'haiku|lean|small.?fast|early|stopping|thinking'`).

## What remains unknown

- **Token cost of thinking on helper calls.** NOT STATED. Settle by running 2.1.293 in a scratch
  profile with debug or stream-json logging and comparing output tokens per helper request
  (title, summary, hook prompt) against the same calls pinned with
  `ANTHROPIC_SMALL_FAST_MODEL=claude-haiku-4-5`.
- **Effort level sent on helper calls.** Not traced; the minified effort resolver name collides
  with other functions. Catalog `default_effort` is `medium`. The same request log settles it
  (`output_config.effort`).
- **Whether the API accepts an omitted `thinking` field as adaptive for Haiku 5.5 on the fleet's
  plan.** Vendor says yes; no live request was made.
- **Whether teammates get the `CLo` section.** `FKt` takes a `teammate` trait, which suggests
  teammates use the default builder, but the teammate launch path was not traced. Settle by dumping
  a Haiku 5.5 teammate's system prompt and searching for "The reasoning effort setting changes".
- **Whether Workflow `agent()` workers follow the subagent path.** Inferred yes (same `DWt` notes
  block appears in this worker's own prompt); not traced in the binary.
- **Lean prompt size delta** for a Haiku 5.5 Explore request versus Haiku 4.5. Settle by reading
  first-turn input tokens in both arms.
- **Live values** of `tengu_idempotent_wolf`, any server-served capability set, and any
  server-supplied replacement for the section. These are server data.
- **Truncation of the three small-`max_tokens` helper calls** on Haiku 5.5. Not measured.
