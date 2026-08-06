# Decision: do NOT set `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT` — parity already holds for every model we run

**Recommendation (one sentence):** Leave the variable unset on all five config dirs — system-prompt
parity across the four accounts is **already true for every session model we actually route to**
(Opus 5, Opus 4.8, Fable 5 all carry the `lean_prompt` capability, which short-circuits the divergent
GrowthBook gate), and setting `=0` would not restore a parity that was never broken: it would add a
**measured +37,143 tokens to every request on every account**.

Backlog item `ddb1b2940432`. Source: session `05ed2d55` GrowthBook divergence audit, 2026-08-05.
Binary under test: `@anthropic-ai/claude-code` **2.1.220** (`~/.claude-220/.../bin/claude.exe`).

---

## 1. The premise inverts under inspection

The item was filed on the belief that `tengu_velvet_tide=true` on next2 forces a SIMPLE system prompt
there while the other three accounts get the full one, and that `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=0`
would force everyone onto the same prompt. The gate is real and next2 really does diverge — but the
gate is **unreachable for the models we run**.

The decision function, extracted verbatim from the 2.1.220 binary (`TT` = *"use the simple system
prompt?"*):

```js
TT = Vr((e) => {
  if (!e) return false;                                          // no model → FULL
  if (Yt(process.env.CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT)) return true;   // env truthy → SIMPLE
  if (su(process.env.CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT)) return false;  // env falsy  → FULL   ← the proposed "=0"
  if (!oug(e)) return true;                                      // lean_prompt model → SIMPLE
  if (Ke("tengu_velvet_tide", false)) return true;               // ← the diverging gate
  return Jcg(e);                                                 // per-model server override
})

function oug(e) {
  if (Qje(e)) return false;                                      // /-eap($|\[)/i
  let t = lo(e);
  if (LN(t, "lean_prompt") || t === "claude-mythos-5") return false;   // ← Opus 5 exits HERE
  if (t.includes("claude-3-") || t.includes("haiku") || t.includes("sonnet")
      || t === "claude-opus-4-0" || t === "claude-opus-4-1" || t === "claude-opus-4-5"
      || t === "claude-opus-4-6" || t === "claude-opus-4-7") return true;
  return !rm();
}
```

`claude-opus-5` declares `lean_prompt` in its capability list, so `oug()` returns `false`, `!oug(e)`
returns **true**, and `TT` returns SIMPLE — **two branches above the `Ke("tengu_velvet_tide")` read**.
No GrowthBook value is consulted at all. There is no account-varying input on that path, so parity is
not a policy we need to enforce; it is a structural property of the model's capability list.

Which models carry `lean_prompt`, from the binary's own model registry:

| Model | `lean_prompt` | Gate reachable? |
|---|---|---|
| `claude-opus-5` — `lead_default`, `default_teammate`, `research_worker` | **YES** | no — short-circuits |
| `claude-opus-4-8` — `opus_prior` | **YES** | no — short-circuits |
| `claude-fable-5` — `frontier_discovery`, `teammate_frontier`, `workflow_judge` | **YES** | no — short-circuits |
| `claude-sonnet-5` — `workflow_synthesis_worker` | no | **yes** |
| `claude-haiku-4-5` — `research_retrieval` (Explore tier) | no | **yes** |
| all `claude-3-*`, `sonnet-4-*`, `opus-4-0…4-7` | no | yes (unrouted) |

## 2. Measured, not reasoned

Static reading is not a measurement, so the claim was tested with a within-account discriminator that
holds hooks, settings, cwd and project context constant and varies only the env var. If next2 were
already on SIMPLE via the gate, its `=0` delta would match next's; if the gate had reached Opus 5, the
delta would collapse to ~0.

Method: `claude.exe -p "Reply with the single word: ok" --model claude-opus-5 --output-format json`
from `/tmp`, total input = `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`.

| Config dir | Account | `tengu_velvet_tide` | default | `=0` | delta |
|---|---|---|---|---|---|
| `~/.claude-next` | next | false | 156,124 | 193,267 | **+37,143** |
| `~/.claude-secondary` | **next2** | **true** | 155,955 | 192,820 | **+36,865** |

Two readings carry the verdict:

1. **At default the diverged account and the clean account agree to within 0.1%** (155,955 vs
   156,124). Opus 5 parity already holds — empirically, not just by construction.
2. **`=0` costs ~+37K tokens on every request, on both accounts**, replicated within 0.8%. On a 200K
   window that is ~18% of the context permanently consumed before any work begins.

## 3. The instrument cannot be scoped to the models that actually diverge

The env var is read at branches 2–3, **above** the `lean_prompt` check at branch 4. It is therefore
model-blind and unconditionally wins. There is no value, and no placement, that fixes the legacy-model
divergence without also moving Opus 5/4.8/Fable 5:

| Option | Effect on Opus 5 / 4.8 / Fable | Effect on haiku 4.5 / sonnet 5 | Verdict |
|---|---|---|---|
| **unset (status quo)** | SIMPLE everywhere — parity holds | next2 SIMPLE, others FULL — diverges | **CHOSEN** |
| `=0` fleet-wide | **SIMPLE → FULL on all 5 dirs, +37K/request** | parity at FULL | rejected — pays a fleet-wide cost to fix an unrouted-tier mismatch |
| `=0` on next2 only | next2 **+37K/request**, others unchanged | parity at FULL | rejected — trades a cheap subagent-tier divergence for an expensive main-model one |
| `=1` fleet-wide | unchanged (already SIMPLE) | parity at SIMPLE | rejected — no token cost, but silently downgrades the retrieval/synthesis tiers on three accounts to buy alignment we have no evidence we need |

The remaining server-side lever, `Jcg` → `GFc("simple_system_prompt", …)`, reads `XR()` →
`clientDataCache` / `clientDataCacheSlots`, which is Anthropic-pushed client data rather than a user
setting, and can only force SIMPLE, never FULL. It is not a surgical alternative either.

## 4. What genuinely remains (not this item)

The divergence is **not** entirely inert, and that correction matters: two roles do route to
non-`lean_prompt` models, so on next2 they receive a different system prompt than on next/next3/next4 —

- `research_retrieval: claude-haiku-4-5` — the Explore tier, ~25% of research slots
- `workflow_synthesis_worker: claude-sonnet-5` — Workflow bulk synthesis

That is a subagent-tier prompt difference on one of four accounts, with no measured quality signal in
either direction. It belongs to the sibling item **`29d1eba690a3`** (still open), whose more serious
half is `tengu_velvet_mallet_opus_5=true` on next2 disabling the native read-before-write guard. This
document settles only the `velvet_tide` / system-prompt half: the env var is the wrong instrument for
it, and no action is warranted on the routed models.

## 5. Re-deriving this rather than trusting it

Every number here decays with the binary and with a server-side rollout that we cannot set and that
already moves between audits. Re-derive rather than quote:

```sh
# current gate value per account (next2 = ~/.claude-secondary — include it; a four-dir sweep misses it)
for d in ~/.claude ~/.claude-next ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary; do
  python3 -c "import json,sys;g=json.load(open('$d/.claude.json')).get('cachedGrowthBookFeatures',{});print('$d',g.get('tengu_velvet_tide','<ABSENT>'))"
done

# does the current default model still short-circuit? (delta ≈ +37K ⇒ yes, on SIMPLE; delta ≈ 0 ⇒ gate reached it)
strings -n 6 ~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe \
  | grep -oE 'function oug[(][^)]*[)][{].{0,300}'
```

Note the population trap this audit hit once: `~/.claude-secondary` is easy to omit when sweeping
"the four accounts", and omitting it reads the divergence as already resolved. Enumerate the config
dirs from `~/.claude/accounts.json`, never by hand.
