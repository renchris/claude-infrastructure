# `claude setup-token` is inference-only by server-side construction — backlog `170a3b38f8c9` refuted

**Date:** 2026-09-08 · **Subject:** cc-backlog `170a3b38f8c9` ("SETUP-TOKEN v2 — VIABLE and
ADDITIVE") · **Method:** read out of the 2.1.260 binary
(`~/.claude-260/node_modules/@anthropic-ai/claude-code/bin/claude.exe`), no token minted.

## The verdict

The item's plan step (1) — *"mint ONE token, wire ONLY that account, test image-paste + /status +
MCP + a real wave"* — **should not be executed as written.** Wiring an account with the loader as
it stands degrades that account **permanently and on every launch**, not only when the Keychain
credential has died. The item's central cost claim, *"at zero cost to quota/routing"*, is true of
the **quota spine** and false of the **session**.

Two facts the item filed as UNKNOWN are now settled from the binary, without minting anything.

**But "nobody ran the experiment" would be the wrong lesson, and it is the one I reached for
first.** The experiment WAS run, thirty-six days earlier and properly — see § How this survived a
correction below. The finding was not missing; it had been buried by a correction that was itself
correct.

## Fact 1 — the grant is narrowed server-side, and no env var can widen it

`setup-token` calls the OAuth flow with `inferenceOnly` hardcoded true:

```js
let Y = await ve.startOAuthFlow(async (D) => K(D), {
    loginWithClaudeAi: pe,
    inferenceOnly: R === "setup-token",          // ← hardcoded for this mode
    expiresIn:     R === "setup-token" ? S ?? LU : void 0,   // LU = 31536000 (1 year)
    orgUUID: ze
})
```

and the authorize-URL builder resolves the requested scope set from exactly that flag:

```js
function Tzt({ …, inferenceOnly: f, oauthClient: M, … }) {
  …
  let x = M ? M.scopes : f ? [ry] : d0n;         // ry = "user:inference"
  D.searchParams.append("scope", x.join(" "));   // d0n = the full five-scope set
```

So the **authorize request itself asks the server for `["user:inference"]`**, where an interactive
`/login` asks for `d0n` = `user:profile user:inference user:sessions:claude_code user:mcp_servers
user:file_upload`. `formatTokens` then records `scopes: VEt(a.scope)` — *the scope string the
server returned*. The token is minted at one scope. This is not a client-side display default.

**Corollary — do not reach for `CLAUDE_CODE_OAUTH_SCOPES`.** That variable feeds
`$B(e=["user:inference"])`, which sets only the client's *local belief* about its own scopes.
Setting it would not widen the grant; it would make the client attempt calls the server rejects,
converting clean client-side "feature disabled" messages into 401s. Anthropic's own BYOC path
pairs the two variables (`CLAUDE_CODE_OAUTH_TOKEN` + `CLAUDE_CODE_OAUTH_SCOPES: "user:inference
user:ccr_inference user:file_upload"`) precisely because it mints its token with those scopes.

## Fact 2 — the env token shadows the Keychain unconditionally

The item's framing — insurance that engages when the monthly login lapses — assumes the env token
is a *fallback*. It is not. The credential resolver returns on it before the Keychain is ever read:

```js
function bfe(){
  if (lo()) return null;
  if (a.CLAUDE_CODE_OAUTH_TOKEN) return {          // ← returns HERE
      accessToken: a.CLAUDE_CODE_OAUTH_TOKEN,
      refreshToken: null, expiresAt: null,
      scopes: $B(), … };
  let e = cx();
  …
  let d = _n().read({fromStoreCopy:!0})?.claudeAiOauth;   // ← unreachable while the var is set
  if (d?.accessToken) return d;
```

A wired account therefore pays the scope loss on **every launch, forever**, to insure against a
roughly monthly event — and one the fleet already has an autonomous path through (`cc-relogin`
Phase 1 headless refresh, Phase 2 unattended OAuth in the account's own auth-browser profile).

## What the narrowing actually costs, by name

Each degrades **quietly** — a skipped connector, an unresolved org, a disabled extension — which
is what makes silent arming the real hazard.

| Capability | Under a setup-token | Evidence |
|---|---|---|
| Claude in Chrome | **off** | server-validated at `/api/oauth/validate`; the binary's message names *"env-var and setup-token sessions default to `user:inference` only"* |
| claude.ai org connectors | **off** | `[claudeai-mcp] Missing user:mcp_servers scope` — 2 `.includes()` gates + 1 `OG()` |
| org / profile resolution | **off** | `/api/oauth/profile` yields no org UUID; the GitHub-app check degrades to a *deterministic* "assuming app not installed" |
| locally-configured MCP (motion-plus, ms365) | **unaffected** | the binary explicitly exempts `managed-mcp.json` / `.claude.json` / `.mcp.json` from the scope check |
| image upload (`user:file_upload`) | **unknown** | **0** client-side gates on this scope, so nothing blocks it locally; whether the server honours an upload on an inference-only bearer is the one residual that genuinely requires a mint |

The item guessed `user:mcp_servers` was "probably not a loss" because motion-plus/uidotsh use their
own OAuth. **That guess holds** — it is now verified rather than assumed. It is the only one of the
item's three guesses that survived.

## How this survived a correction — the re-mint's actual root cause

This idea has cycled three times, and the loop is more instructive than the finding.

1. **`9737a84c`** ran the gating experiment against a real minted token, *with a positive control*:
   `setup-token` (inference-only) → **HTTP 403** at `/api/oauth/usage`; keychain (five scopes) →
   **200**. Textbook — the control makes the failure attributable rather than bare. It concluded
   "Method A is dead", because a 403 there would blind `/accounts` and the router.
2. **`dd02f7df`** refuted that conclusion, and was **right to**: `bin/claude-accounts` bearers the
   credential it read from the Keychain, never the env var, so the quota spine cannot be blinded.
3. But it then published the claim this item inherited — *"ADDITIVE … at no cost to quota or
   routing"*, which the backlog row compressed to **"at zero cost"**.

**Refuting one objection to a claim does not establish the claim.** Step 2 disposed of the
*quota-blinding* objection and nothing else. The 403 from step 1 was never an argument about quota
in the first place — it was direct evidence that **the token is scope-narrowed at the server**, and
that fact survived the correction completely intact. It was demoted to a footnote about one
untested scope (`user:file_upload`) because the objection it had been *attached to* had fallen.
Nobody asked what the other three scopes cost, or whether the env token displaces the Keychain
*inside* a session.

That last question is the one the framing made unaskable. Both prior sessions modelled the two
stores as *"separate stores that never touch"* — true of the **external reader** (`claude-accounts`
does read the Keychain directly) and simply assumed of every other consumer. Inside a session the
resolver returns on the env var first, so the stores touch in the only place that matters.

The generalisable form of each, since both are cheap to repeat:

- **A correction inherits the burden of the claim it rescues.** Refuting objection *O* to claim *C*
  establishes ¬*O*, never *C* — and any measurement taken in service of *O* outlives it. Re-file the
  surviving measurement under its own heading before closing the correction. (Sibling rule, opposite
  direction: *cause refuted ≠ effect discharged*.)
- **A credential source that takes precedence is not a fallback.** Before calling a supplementary
  token "insurance", read the resolver's *return order*. Insurance engages when the primary fails;
  this one engages always, and the primary becomes unreachable.

## What was fixed instead

The loader landed by `29911f226` is correct on the hazard it was built for (cross-account
cross-wiring: set-or-unset, fail-closed) and stays exactly as written. Its defect is that it
**arms silently** — the moment a token file appears under `~/.claude/oauth-tokens/`, that account
loses four scopes on every launch with no indication anywhere. It is a loaded gun with the safety
off, and the store is 0700-prepared and waiting.

This commit makes it loud: two unguarded `print -ru2` lines naming the degradation and the exact
cure (`rm <tokfile>`), with no opt-out variable — a warning each participant can switch off is not
a warning (`0fd5dc64f`, the same defect in cc-bats). The loader's comment block, which asserted the
quota-spine safety and said nothing about scopes, now carries both facts above.

Red-proof: `tests/config-mirror-oauth-token.bats` cases 13 and 14 fail against the pre-fix loader
and pass after; cases 15 and 16 are guards and are labelled as such in the file rather than
implied to be evidence.

## RULED: dropped — do not re-open without new evidence

Put to the operator as decision packet `a90e1ac2597e` (drop entirely vs. build a loader that
exports the token only when the Keychain credential has actually died), at conviction 65 with a
recommendation to drop. **Operator ruled: drop, 2026-09-08.** No token files are to be created;
the automated re-login path stays the only cure for a lapsed login.

The three arguments, recorded so the fourth re-mint has to beat them rather than rediscover them:

1. **The gap is already covered.** `cc-relogin` drives the monthly cliff unattended — headless
   refresh grant, then unattended OAuth in the account's own auth-browser profile. A long-lived
   token only earns its keep when *both* legs fail.
2. **It trades a loud failure for a quiet one, and the quiet one is worse.** A lapsed account stops
   cleanly and drops out of the routing pool, which fails closed on absent quota. A token-bearing
   account keeps running at one scope with every loss silent. Over an unattended wave, "stopped at
   02:00" is recoverable; "ran six hours subtly wrong" is not.
3. **The conditional version adds a new trigger for exactly that risk.** Judging credential death
   in the launcher hot path on every launch means a wrong "dead" verdict silently downgrades a
   *healthy* account — failure 2, now reachable by a bug rather than by policy.

**What would legitimately re-open this** (either one, not a re-argument):
- the residual measured — whether the API honours an image upload on an inference-only bearer —
  **and** a decision that a session should never stop even at the price of running degraded; or
- a measured failure rate for the unattended browser re-login leg. Argument 1 rests on that leg
  working, and nothing on disk counts it. If it fails often, the token becomes real insurance.
  Counting it is the one measurement that would move this above 90% either way.
