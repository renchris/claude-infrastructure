# D1 — Who answers a permission prompt while the operator is asleep?

Packet `1df4081249d2` (class C, open, prior conviction 60). Read-only research, 2026-09-09.
Binary under test: `/Users/chrisren/.claude-260/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (2.1.260, 198,289,440 B).
Controls: `~/.claude-220/...` (2.1.220), `~/.claude-219/...` (2.1.219).

---

## The answer, first

**Run the decider in SHADOW; delete the "enforce the compound test-fixture class" half — that class
is 100% fenced by the decider's own indirection rule and would clear 0 of its 205 prompts and 0 of
its 499 blocked hours.** Both premises the packet listed under `decider-owns` are now measured and
one is refuted: a PreToolUse `allow` does **not** bypass `permissions.deny` or `permissions.ask` on
2.1.260 — and did not on 2.1.220 either, so the decider's docstring was wrong when written, not
merely stale. The risk axis inverted: the danger is not false ALLOWs removing a human, it is false
ASKs **adding** humans — 73.7% of the prompts the classifier currently resolves in under 10 seconds
would be converted by the decider into a hard prompt the classifier is structurally forbidden to
clear.

---

## (a) Does a PreToolUse hook `permissionDecision: allow` bypass deny / the ask list / the classifier?

### NO. Deny rules are evaluated FIRST and override the hook.

The resolver is one function, `jio` (aliased `cRe`), at absolute binary offset **162,562,900–162,563,700**
(js-region offset 62,562,900). Verbatim minified source, reformatted only by line breaks:

```js
async function jio(e,n,r,o,d,f,_){
  if(_Xe(n))return{decision:{behavior:"allow",updatedInput:r},input:r};
  let E=o.requireCanUseTool;
  if(e?.behavior==="deny")return t(`Hook denied tool use for ${n.name}`),{decision:e,input:r};
  if(e?.behavior!=="allow"&&e?.behavior!=="ask")return{decision:await d(n,r,o,f,_),input:r};
  let C=e.behavior,D=e.updatedInput??r,
      N=await Mv(n,D,{...o,toolUseId:_},{hookUpdatedInput:e.updatedInput});   // <- RULE EVALUATION
  if(N?.behavior==="deny")
     return t(`Hook returned '${C}' for ${n.name}, but deny rule overrides: ${N.message}`),
            {decision:N,input:D};
  if(N?.behavior==="ask"){
     let F=C==="ask";
     if(F)o.toolDecisions??={};
     return t(`Hook returned '${C}' for ${n.name}, but ask rule/safety check requires full permission
               pipeline${F?" (hookAskFloor — a classifier allow re-surfaces as this ask)":""}`),
            {decision:await d(n,D,F?{...o,hookAskFloor:!0}:o,f,_),input:D};
  }
  if(C==="allow"){
     if(E)return t(`Hook approved tool use for ${n.name}, but canUseTool is required`),
                  {decision:await d(n,D,o,f,_),input:D};
     if(!n.requiresUserInteraction?.()&&VH(n,ce(o))==="auto"&&I("tengu_virtual_knuth",!1)){
        ... i("tengu_auto_mode_hook_allow_funneled",{...}),
        t(`Hook approved tool use for ${n.name}, but auto mode requires classifier adjudication`),
        o.toolDecisions??={},
        return {decision:await d(n,D,{...o,hookAllowVouched:!0},f,_),input:D}
     }
     return t(n.requiresUserInteraction?.()
              ?`Hook satisfied user interaction for ${n.name} via updatedInput`
              :`Hook approved tool use for ${n.name}, bypassing permission prompt`),
            {decision:e,input:D}
  }
  return{decision:await d(n,D,o,f,_,e),input:D}
}
```

Resolution order, read off that code:

| # | Condition | Outcome |
|---|---|---|
| 1 | hook says `deny` | deny, short-circuit |
| 2 | hook says `allow`/`ask` | **`Mv(...)` — the rule engine — runs next** |
| 3 | rule says **deny** | `"but deny rule overrides"` → **deny wins over hook allow** |
| 4 | rule says **ask** | `"but ask rule/safety check requires full permission pipeline"` → full pipeline; if the hook also said ask, `hookAskFloor:true` |
| 5 | rules silent + `requireCanUseTool` | full pipeline |
| 6 | rules silent + auto mode + gate `tengu_virtual_knuth` | `hookAllowVouched:true` → **full pipeline, "auto mode requires classifier adjudication"** |
| 7 | otherwise | `"bypassing permission prompt"` |

### Version A/B — the docstring was wrong at the time, not stale

```
for v in 219 220 260; do B=~/.claude-$v/.../claude.exe;
  for p in 'but deny rule overrides' 'hookAskFloor' 'auto mode requires classifier adjudication' \
           'tengu_auto_mode_hook_allow_funneled' 'permissionBehavior'; do
    echo "$p => $(gtimeout 180 /usr/bin/grep -a -o "$p" "$B" | wc -l)"; done; done
```

| string | 2.1.219 | 2.1.220 | 2.1.260 |
|---|---:|---:|---:|
| `but deny rule overrides` | **2** | **2** | **2** |
| `hookAskFloor` | 4 | 4 | **6** |
| `bypassing permission prompt` | 2 | 2 | 2 |
| `auto mode requires classifier adjudication` | 0 | 0 | **2** |
| `tengu_auto_mode_hook_allow_funneled` | 0 | 0 | **2** |
| `permissionBehavior` | 38 | 38 | **56** |

* The deny-override existed on **2.1.220**, the very build the decider was measured on. So
  `hooks/model-permission-decider.py:39-41` — *"A hook emitting `allow` BYPASSES the permission
  system COMPLETELY … an `allow` sailed past the allowed-working-directory write guard"* — drew a
  world-shaped conclusion from one guard. The cwd write guard is not a `permissions.deny` rule; the
  experiment bounded **that guard**, not the permission system.
* **New in 2.1.260 only:** under `defaultMode=auto`, a hook `allow` is funneled into the classifier
  rather than bypassing the prompt. Gated on `I("tengu_virtual_knuth",!1)` — a remote feature gate
  whose local default argument is `false` (inferred from the two-arg `I(name, default)` shape).

### Docs cross-check — concordant, verbatim

`https://code.claude.com/docs/en/hooks`, PreToolUse decision control:

> **`permissionDecision`**: `"allow"`, `"deny"`, `"ask"`, or `"defer"`. On `"allow"`, the tool call
> proceeds without the permission system. On `"deny"`, Claude Code blocks it. On `"ask"`, Claude Code
> prompts you. On `"defer"`, the normal permission flow applies: Claude Code checks deny rules, the
> ask list, and auto mode. If a deny rule matches, it blocks; if the ask list matches, it prompts; if
> auto mode is on, it allows. **Hooks run before the classifier, so a hook's `"allow"` verdict does not
> bypass deny rules or the ask list—the normal flow still applies after the hook returns unless the
> hook chose `"defer"`.** A hook's `"deny"` blocks the call and stops the flow.

Two independent instruments agree. Note the docs' first sentence ("proceeds without the permission
system") is contradicted by their own fourth sentence; the binary settles it in favour of the fourth.

### A near-miss worth recording (methodology)

`grep -a 'permissionDecision==="allow"'` returns **exactly one** hit fleet-wide, and it is a
*drop-recorder*. That reading — "allow is stripped, it cannot bypass anything" — is **false**. The
real consumer uses a `switch`, not `===`:

```js
switch(e.hookSpecificOutput.permissionDecision){
  case"allow":N.permissionBehavior="allow";break;
  case"deny": N.permissionBehavior="deny",N.blockingError={...};break;
  case"ask":  N.permissionBehavior="ask";break;
  case"defer":N.permissionBehavior="defer";break;
  default: throw Error(`Unknown hook permissionDecision type: ...`)}
```
(function `nme`, js offset 65,484,636 → absolute 165,484,636; 12 call sites.)

The one `===` site lives in `D2r`/`MLe`/`y5t`, which **is** a stripping path — but it is the
**cloud-session** hook runner, not the local one. Its caller (js 61,574,590) logs
`` `cloud ▸ ${De} ▸ …` `` and refuses interpreters with
*"Not running hooks through … for the cloud session: on this machine that name leads to a file the
session can write."* Local `settings.json` hooks do not go through it. *(A lookup miss is not
absence — MEMORY `lookup-miss-is-not-absence`.)*

---

## (b) Does a PreToolUse `ask` still reach the human under `permissions.defaultMode=auto`?

### YES — and there is a named mechanism whose only purpose is to guarantee it.

`hookAskFloor`. Set in `jio` step 4; consumed at js 62,534,510 (absolute 162,534,510):

```js
let be=E.hookAskFloor===!0;
if(be&&!de&&N.shouldAvoidPermissionPrompts)return bae(C.message);
let Ce=(Nn)=>{
  if(de)return{...C,...Nn,decisionReason:DZe(C,Nn.decisionReason)};
  if(be){ if(F==="dontAsk")return{behavior:"deny",decisionReason:{type:"mode",mode:"dontAsk"},message:$Te(e.name)};
          return{...C,updatedInput:Nn.updatedInput} }      // <- stays ASK
  return{behavior:"allow",...Nn}                            // <- normal auto-mode conversion
}
```

`Ce` is the *classifier-approved* continuation. Without the floor it returns `{behavior:"allow"}`;
**with** the floor it returns `C` — the ask — unchanged. That is precisely the log string
`(hookAskFloor — a classifier allow re-surfaces as this ask)`. Two further fast paths bail on it:
`n6n(...)` requires `n.hookAskFloor!==!0`, and `Fa(...)` returns to the full path when
`i.hookAskFloor===!0` (js 68,020,429 / 68,021,023).

Docs concur: *"On `"ask"`, Claude Code prompts you."* — and `defer` exists as a **separate verb** for
"apply the normal flow", so `ask` cannot be a synonym for it.

**Two exceptions, both real:**
* mode `dontAsk` → the ask becomes `{behavior:"deny"}`.
* `shouldAvoidPermissionPrompts` (headless / non-interactive) → `bae(C.message)`, not a prompt.

**Honest gap.** `hookAskFloor` is set only when a *rule* also returned ask. Hook-ask-with-silent-rules
takes the final line, `d(n,D,o,f,_,e)`, whose 6-argument form I did not trace end-to-end. Three
converging instruments (docs sentence, the floor mechanism's existence, the decider's own 2026-08-12
empirical arm on 2.1.220) say the ask still prompts; **that specific arm is inferred, not read.**

---

## (c) What the decider would actually do on the real slow stratum

### Can it be replayed offline? Partly — and the part that matters is exact.

`consult_model()` shells out to `CLAUDE_BIN -p … --model claude-haiku-4-5-20251001`
(`CLAUDE_BIN` defaults to `/Users/chrisren/.claude-220/node_modules/.bin/claude`, symlink present).
That needs a live authenticated account, so **the model verdict cannot be replayed offline.**

It does not need to be. `main()` runs `already_allowed()` → `fence()` → *then* the model, and
`fence()` runs **a second time on the model's ALLOW** (`recheck`). The docstring's own invariant is
*"the model's verdict can only ever NARROW."* Therefore **the set of commands that clear `fence()` is
an exact upper bound on what the decider can ever ALLOW.** Everything below replays the real module
(`importlib` on `hooks/model-permission-decider.py`), reading the operator's live
`~/.claude/settings.json` — `ask=6 deny=30 readable=True` — and touching nothing.

### Corpus

```
cd ~/.claude/autonomy/permission-archive && gtimeout 120 cat *.jsonl > $S/permarch.jsonl   # 3,919
CUT=$(( $(date +%s) - 30*86400 ))                                                          # 1786384239
jq -c --argjson c "$CUT" 'select(.ts>=$c)' $S/permarch.jsonl > $S/perm30.jsonl             # 3,064
jq -c 'select(.tool_name=="Bash")' $S/perm30.jsonl | wc -l                                 # 2,987
jq -c 'select(.tool_name=="Bash" and .waited_s>300)' $S/perm30.jsonl | wc -l               #   488
```

### Slow stratum (`waited_s > 300`), n = 488 — `scratchpad/replay.py`

```
   367  FENCED_ask                          855.0 blocked hours
    77  CLEARS_FENCE_allow_candidate        168.5 blocked hours
    44  no_command_text (truncated rows — replay abstains)
     0  already_allowed
   fence reasons: indirection 257 · untokenisable 55 · ask_rule 53 · deny_rule 2
```

**Ceiling: 77/488 = 15.8% of slow prompts (17.3% of the 444 decidable), 168.5 h of 1,023.5 h = 16.5%
of the slow-stratum hours.** And that is before the model narrows it.

### False-allow audit of the 77 — `scratchpad/analyse.py`

* **0 of 77 match `permissions.ask` or `permissions.deny`.** Positive control passes: the fence read
  the live rules and rejected 53 ask-rule and 2 deny-rule hits from this same stratum, so the null is
  the fence working, not the instrument failing.
* soft_deny-shaped: **7 commands total** — 5 `chmod/chown` (none are the denied `chmod 777` /
  `chmod -R 777` forms), 1 `pkill -f "next dev"` against a dev server the session itself started,
  1 `cat > "$D/cfg/settings.json"` where `D=/tmp/hs-localmerge` — **a fixture's settings file, not the
  operator's**, i.e. a false positive of my probe rather than a false allow.
* Head-verb histogram of the 77: `curl` 33 · `cd` 21 · `export` 10 · `rm` 6 · `set` 2 · other 5.
  `curl` is the dominant allow-candidate class; note `wget` is in `permissions.deny` and `curl` is not.

**Verdict on the packet's stated worry: the false-allow exposure on the slow stratum is ~0–7 of 77,
and none of it crosses a gate the operator wrote.** The fence does what it claims.

### The enforcement scope named in the recommendation clears NOTHING — `scratchpad/fixture.py`

| shape | n | blocked h | decider verdict |
|---|---:|---:|---|
| `T=$(mktemp -d)` | 87 | 193.2 | **87 ASK / 0 allow** |
| `cd <wt> && python3 - <<'PY'` | 4 | 11.7 | **4 ASK / 0 allow** |
| broad fixture class (`$(mktemp`, any heredoc, or `cd X &&`) | 205 | 499.1 | 188 ASK / 17 allow (71.7 h) |

Why: `$(` is matched by `INDIRECTION` and fenced **unconditionally, without being understood** — by
design (`model-permission-decider.py:107-120`). `python3 -c "` additionally fails `shlex.split`.
Of the 188 fenced fixture commands, 157 are fenced on indirection alone.

**"ENFORCE only for the compound test-fixture class" is a null policy.** The named class is exactly
the class the fence is structurally incapable of clearing.

---

## Adversarial pass — the failure the packet is not worried about is the one that bites

The decider emits `ask` on **every** error path: fenced command, unreadable settings, budget
exhaustion, model timeout, crash. Combined with (b) — a hook `ask` is a floor the auto-mode classifier
may not clear — every one of those is a **human prompt that would not otherwise exist**.

**Full Bash traffic** (`~/.claude/logs/bash-commands.log` + `…20260909T140248Z.gz`, ~3.5 days) —
`scratchpad/bashlog.py`:

```
bash calls parsed: 49583
  28137   56.7%  FENCED -> decider emits ask -> HUMAN PROMPT
  13640   27.5%  clears fence -> costs a MODEL CALL (budget)
   7806   15.7%  already_allowed
  fence reasons: indirection 14233 · untokenisable 13851 · deny rule 45 · ask rule 8
```

**Structured-archive control, by wait stratum** (no log-parsing risk — `tool_input.command` is JSON) —
`scratchpad/strata.py`:

| stratum | n | ASK (fenced) | ALLOW candidate |
|---|---:|---:|---:|
| **fast < 10 s** (classifier auto-resolves, incl. overnight) | 1,775 | **1,308 = 73.7%** | 452 = 25.5% |
| 10–300 s | 724 | 558 = 77.1% | 140 = 19.3% |
| slow > 300 s | 488 | 367 = 75.2% | 77 = 15.8% |

Both instruments agree the fence is a majority-ASK function. Consequences of ENFORCE as written:

1. **Prompt multiplication.** ≥1,308 prompts per 30 days that today resolve in seconds — the ones
   A05 §1c showed resolving *at full rate while the operator is asleep* — become hard prompts.
   Against a baseline of 2,987 Bash prompts / 30 d, and 8,000/day implied by the full-traffic rate,
   this is the opposite of the packet's goal.
2. **Budget is ~10× under-sized.** 13,640 fence-clearing calls in 3.5 days ≈ 3,900/day against
   `PER_DAY_MAX=400` / `PER_SESSION_MAX=40`. Exhaustion emits `ask` too, so the decider degrades
   into a pure prompt generator by mid-morning.
3. **`already_allowed()` under-counts badly** — 15.7% here vs the 63.1% of Bash invocations
   `cc-permission-audit` measures as matching an allow rule. It requires *every* `\n`-split segment to
   match a prefix, so any multi-line command fails it. This is what drives (1) and (2).
4. **`untokenisable` is 27.9% of all traffic** (13,851 of 49,583) — `segments()` splits heredoc
   bodies and Python source on `\n` and feeds them to `shlex.split`. That is a parser defect
   producing prompts, not a safety judgement.

### Operational facts that block "run it in shadow" from being a no-op

* **The decider is not wired.** `~/.claude/settings.json` `hooks.PreToolUse` matcher `Bash` contains
  only `smart-bash-allowlist.sh` and `rm-safe-allowlist.sh`, **both `timeout: 5`**. The decider needs
  `timeout: 60` (`DEADLINE_S=38`, and its docstring says a hook that overruns is silently discarded).
  So this is a first run, not a re-run.
* `MITL_MODE` already defaults to `"shadow"` — in shadow it logs to
  `~/.claude/autonomy/mitl-decider/decisions-YYYY-MM.jsonl` and emits nothing.
* Its default `CLAUDE_BIN` is the **2.1.220** binary while sessions run 2.1.260.
* Shadow still spends a real Haiku call per fence-clearing command — ~3,900/day at current traffic
  unless `PER_DAY_MAX` is raised or the shadow run is restricted.

---

## What is still the operator's after this research

`I("tengu_virtual_knuth", false)` is a **remote feature gate**. It decides whether, under
`defaultMode=auto`, a hook `allow` is honoured directly or funneled into the classifier. It can flip
without a version bump, and no local measurement can bound it. Accepting a model-approver whose
effective authority is set by a vendor-side flag is a value call, not a measurement.

Everything else the packet listed as unmeasured is now measured.
