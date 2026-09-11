# `tengu_propose_goal` is still OFF at 2.1.267 — backlog `2a65b9bf722d` re-anchored, NOT closed

**Date:** 2026-09-10 · **Subject:** cc-backlog `2a65b9bf722d` ("ProposeGoal (`tengu_propose_goal`)
is default-off upstream — adopt when the flag flips", filed from
`docs/research/exhaustive-drive-2026-09-08/` A12 R6 / SYNTHESIS row 15) · **Method:** read out of
the **2.1.267** native binary (`/opt/claude-code/bin/claude`, ELF, 217,013,744 B) and the
GrowthBook feature cache, on an Anthropic-managed cloud VM. No flag was flipped, no setting was
written, no code changed.

## 🚦 Disposition: this row STAYS OPEN

This is a `not-yet-true` watch row and its premise is **NOT REFUTED**. The correct action is to
**re-anchor it to this note and leave it open** — *not* `cc-backlog done`. Closing it retires the
watch on the one upstream feature that implements the operator's standing ask, and nothing else in
the tree is watching that flag. The only thing that should ever close this row is its own falsifier
going true.

What this pass adds over "still off" is the part the row's one line does not carry: **what adoption
actually costs and what it cannot cover**, measured rather than assumed, plus a correction to how
the premise is cited so the next re-check does not come back empty-handed (§4).

## 1. The verdict, and what was run

| Question | Answer at 2.1.267 / 2026-09-10 |
|---|---|
| Is `tengu_propose_goal` on? | **No.** Absent from both feature caches ⇒ the `!1` default applies. |
| Is the gate still default-false? | **Yes**, byte-for-byte: `function cgt(){return I("tengu_propose_goal",!1)}` |
| Was the feature removed upstream? | **No.** `ProposeGoal` 18 occurrences, `modelProposedGoals` 12, `proposal_direct` 2. |
| Is there a local override for the flag? | **Still no.** The settings key can only narrow (`alwaysAsk`) or disable; it cannot turn the tool on past `cgt()`. |
| Dispatcher vintage | `git rev-parse origin/main:bin/cc-dispatch` = `9109de61dc7a…` = the blob that composed the brief. **EQUAL — the dispatcher that fired this is trunk.** |

```
$ jq -r '.cachedGrowthBookFeatures.tengu_propose_goal // "ABSENT"' /root/.claude.json
ABSENT
$ jq -r '.cachedExperimentFeatures | map(select(test("propose"))) | @json' /root/.claude.json
[]
$ jq -r '.cachedGrowthBookFeatures | keys[] | select(test("goal"))' /root/.claude.json
                                        # ← no goal-related key at all
$ date -u -d @$(( $(jq -r .cachedGrowthBookFeaturesAt /root/.claude.json)/1000 )) +%FT%TZ
2026-09-10T18:51:19Z                    # this session's own boot — the cache is FRESH, not stale
```

**Positive control for the instrument** (a cache that reads "absent" for everything proves nothing).
The same file reproduces A12-skeptic2's per-key census exactly: 616 `tengu_` keys · `tengu_saffron_wren`
**true** · `tengu_hushed_lark` **5** · `tengu_rosy_wren` **ABSENT** · `tengu_umber_kestrel` ABSENT.
Three of four match the desk's four config dirs; the fourth (`umber_kestrel`) is the one A12 already
measured as varying per account (F/F/T/F/T), so a fifth value there is expected, not a discrepancy.

This is a **fifth, independent environment** — different `machineID`, different account context, a
cloud VM rather than the desk — agreeing with the desk's four config dirs. The absence is not a
property of one box.

## 2. The gate, re-read at 2.1.267

```js
isEnabled(){ if(Re()||Fn())return!1;      // Re() = !isInteractive()  ·  Fn() = workspace==="remote"
             if(_t())return!1;            // _t() = sessionKind === "bg"
             if(!cgt())return!1;          // ← THE GATE
             let e=vPe(); if(e==="disabled")return!1;
             return P(e),!0 }

function cgt(){ return I("tengu_propose_goal", !1) }      // DEFAULT FALSE — unchanged
function vPe(){ return fI("modelProposedGoals")[0] ?? "auto" }
```

Verified live in this session: `Re()` → `function Re(){return!n().host.launchOptions.isInteractive()}`,
`Fn()` → `function Fn(){return n().surfaceCapabilities.caps().workspace==="remote"}`,
`_t()` → `function _t(){return VW()==="bg"}`.

## 3. What adoption would actually buy, and what it cannot cover

Measured from the tool's `call` body, because the row says "adopt" and nobody has priced it.

**(a) `ProposeGoal` does not set a goal. It enqueues the very slash command we already paste.**

```js
if(!l) return e.recordQueuedGoalOrigin(o,"proposal_direct"),
        S.enqueue({agentId:Ve(), mode:"prompt", value:`/goal ${o}`, origin:{kind:"task-notification"}}),
        {data:{condition:o, askUser:!1}};
```

Both the `ask_user:false` path and the approved-dialog path end in `S.enqueue(… "/goal " + cond)`.
So an adopted path runs through the **same** `/goal` handler, writes the **same**
`{"type":"goal_status","met":false,"condition":…}` attachment, and
`goal_armed_for_pane()` (`scripts/handoff-fire.sh:5361`) — which keys on exactly that attachment —
**works unchanged**. Adoption is a change to *how the command is submitted*, not to what the oracle
reads. That is the cheap half, and it was worth establishing before anyone budgets an oracle rewrite.

**(b) The condition cap is 8× narrower, and our current cap is still right for the typed path.**

| Path | Constant | Value | Enforcement |
|---|---|---|---|
| typed `/goal <cond>` | `Dje` | **4000** | `"Goal condition is limited to ${Dje} characters (got …)"`, nothing set |
| `ProposeGoal` | `rAt` | **500** | throws *"goal condition exceeds the canonicalized-length cap"* before the enqueue |

`scripts/handoff-fire.sh:5322` defaults `GOAL_MAX_CHARS=4000`, citing a 2026-08-08 measurement.
**That number is re-anchored to 2.1.267 today and still holds** — but it is the typed-path cap, and
the 4000 ceiling is unreachable *through* `ProposeGoal`. A condition of 501–4000 chars that
`check_goal_arm` admits today would be rejected on an adopted path. Cheap to satisfy (the repo
already advises "the goal is a POINTER, not the brief"), but it must be known *before* adoption,
not discovered by a peer throwing at fire time.

**(c) Adoption cannot retire the paste path — it covers strictly fewer session shapes than we fire.**

`Re() || Fn() || _t()` excludes non-interactive, `workspace==="remote"`, and background sessions;
`if(e.agentId) throw` excludes subagents; and even the `ask_user:false` branch throws
*"Goal proposals need an interactive session to render the approval prompt"* when `requestDialog`
is undefined. An interactive local iTerm peer — the `handoff-fire.sh` case — qualifies. A cloud
worker, a `--print` run, a `bg` job and every subagent do not. **The iTerm paste path stays.**
Adoption would remove the composer race for one class of fire, not the mechanism.

**(d) Two further blockers on the call path, neither visible from `isEnabled`.**

- **Plan mode** throws (*"Plan mode is active, so a goal cannot be proposed yet"*), and an approval
  that lands *after* plan mode became active is silently **dropped** (`approved_dropped_plan_mode`).
- **`ask_user:false` is not a guarantee.** The effective setting is resolved by `d$n()`, not
  `vPe()`: value set ⇒ that value; unset **but present-and-unresolvable** in a trusted source ⇒
  **`alwaysAsk`**; absent everywhere ⇒ `auto`. `l = (y==="alwaysAsk") || (w!==!1)`, so under
  `alwaysAsk` a direct proposal is **upgraded to a dialog**. On an unattended fired peer that is a
  dialog nobody presses — the undriven-peer failure this repo already pays for. Any adoption must
  therefore assert `auto` at the peer, and the setting is read from `userSettings`/`flagSettings`/
  `policySettings` **only** — *"workspace-resident project and local settings are ignored"* — so it
  cannot be pinned from the repo, and C10 forbids editing the live `settings.json` in place.

## 4. The citation correction — why a naive re-check comes back empty

A12 §3 cites the gate as **`function mct(){…}` @ offset 24137371** and `isEnabled` @ 27060798.
At 2.1.267 the symbol is **`cgt`** and every offset has moved (the binary is now a single native
ELF, not `node_modules/.../cli.js` — the npm tree on this VM still carries an unrelated
`cli.js` at version 2.1.42, and greps against *it* return 0 for all three strings).

A re-check that greps for `mct` finds nothing, which reads exactly like *the feature was removed*
when the truth is *it was minified to a different name*. Same class as `goal-inert-watch.sh`'s own
header note — *"the rename changes nothing this hook does; it changes what a reader who greps the
binary for `vKo` will find, which is nothing."*

⇒ **Cite the gate by its argument, never by its symbol or offset.** The re-measurement, which is
version-proof and costs one command:

```sh
grep -a -o -E 'function [A-Za-z0-9_$]+\(\)\{return [A-Za-z0-9_$]+\("tengu_propose_goal",![01]\)\}' "$CLAUDE_BIN"
```

At 2.1.267 that prints `function cgt(){return I("tengu_propose_goal",!1)}`. A `!0` there — or no
match at all while `grep -a -c -F ProposeGoal` is non-zero — is the real signal that the default
moved.

## 5. The row's falsifier: sound, with one hole worth closing

Stored probe, re-run at dispatch and again here:

```sh
jq -es 'any(.[]; .cachedGrowthBookFeatures.tengu_propose_goal == true)' ~/.claude*/.claude.json   # → false
```

It is **correctly polarized** (it can only ever retract the row) and **correctly scoped**: the
`~/.claude*/` glob matches the config-dir copies and *excludes* `$HOME/.claude.json`, which
A12-skeptic2 measured as stale since 2026-08-11. Keep it.

The hole is freshness. A config dir that has not been launched in weeks answers `false` because
**nobody asked GrowthBook lately**, not because the flag is off — an absence-is-evidence read with
no staleness guard. It fails toward "keep waiting", which is the safe direction, but it makes the
row's `false` unfalsifiable in the limit: once every cache goes stale the probe answers `false`
forever and no reading can ever change it.

**A staleness clause folded into the falsifier cannot fix this**, and the first draft of this note
shipped one that did nothing. Adding `($fresh|length) > 0 and …` is a no-op on the result: `any`
over an empty array is *already* `false`, so the guarded and unguarded probes return the identical
`false` in exactly the case that needed distinguishing. Freshness has to be a **second reading**,
because it answers a question about the *instrument*, not about the flag.

```sh
# (1) FALSIFIER — rc 0 ⇒ the flag flipped; retract the row. Only this arm should ever close it.
jq -es --argjson maxage 604800 'any(
  .[] | select(((.cachedGrowthBookFeaturesAt // 0)/1000) > (now - $maxage));
  .cachedGrowthBookFeatures.tengu_propose_goal == true)' ~/.claude*/.claude.json

# (2) HEALTH — rc 0 ⇒ at least one cache was refreshed inside the window, so (1)'s `false` means
#     "off". rc 1 ⇒ (1)'s `false` means "nobody asked"; go launch a session, do not read it as off.
jq -es --argjson maxage 604800 'any(.[];
  ((.cachedGrowthBookFeaturesAt // 0)/1000) > (now - $maxage))' ~/.claude*/.claude.json
```

Measured against fixtures, both halves, all arms (`$maxage` = 7 d):

| cache set | (1) falsifier | (2) health | reading |
|---|---|---|---|
| fresh, flag `true` | **true, rc 0** | true, rc 0 | **retract the row** |
| fresh, flag absent | false, rc 1 | true, rc 0 | off — keep waiting |
| stale only, flag `true` | false, rc 1 | **false, rc 1** | **uninformative** — the old probe's blind spot |
| no `…FeaturesAt` stamp at all | false, rc 1 | **false, rc 1** | uninformative |
| stale-`true` + fresh-absent | false, rc 1 | true, rc 0 | off — the newer observation wins |
| stale-`true` + fresh-`true` | **true, rc 0** | true, rc 0 | retract the row |
| this VM's real cache | false, rc 1 | true, rc 0 | **off, on a healthy instrument** |

The `true`-flag arms are the load-bearing ones: without them a probe that always returns `false`
looks identical to a correct one, and this row would be waiting on a falsifier that cannot fire.

**And a caution for whoever is dispatched on this row next:** A12 R6's prose falsifier —
*"`ProposeGoal` appears in a lead session's tool inventory"* — is **structurally unobservable from a
dispatched cloud worker**. `Fn()` (`workspace === "remote"`) is checked *before* `cgt()`, so this
session's tool list would lack `ProposeGoal` at 2.1.267 whether the flag were on or off. Reading
one's own tool inventory here yields a confident `false` that carries zero information about the
flag. Use the cache probe (SYNTHESIS row 15 already corrected it to that); the prose form only holds
at an interactive local session.

## 6. What was NOT established

- Whether the flag is on for **any** account anywhere. Absence in five caches is absence of
  observation of a `true`, evaluated for these identities; GrowthBook targeting is per-identity and
  a rollout could reach an account not sampled here.
- Whether an adopted `ask_user:false` proposal actually engages on a fired peer. Unmeasurable until
  the flag flips — no environment on which the tool is enabled exists to test against.
- Any behaviour of the approval **dialog** itself. Never rendered; read only from the call body.

## Files and commands

Subject binary: `/opt/claude-code/bin/claude` (2.1.267, `BuildID 4d6b52dff7c9c7d8c855e4c9a06c81d7c48c2428`).
Flag cache: `/root/.claude.json`, `cachedGrowthBookFeaturesAt` 2026-09-10T18:51:19Z, 621 keys.
Every command in this note is quoted in full at its use site; nothing here needs the desk to reproduce
except the `~/.claude*/` glob in §5, which is desk-only by construction.
