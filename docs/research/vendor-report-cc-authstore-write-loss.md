# Vendor report — a rotated OAuth refresh token can be lost silently

**Product:** Claude Code · **Version measured:** `2.1.220` (darwin-arm64, `bin/claude.exe`) ·
**Measured:** 2026-08-08, by reading the shipped bundle · **Upstream tracker:**
<https://github.com/anthropics/claude-code/issues> (per the package's own `bugs.url`)

> This file is the SUBMITTABLE artifact. The investigation that found it is
> `forced-relogin-rootcause-2026-08-02.md` UPDATE 3 § *Known-open, filed rather than fixed*; that
> document owns the fleet evidence, this one owns the mechanism. Re-check any version with
> `scripts/cc-authstore-probe.sh <binary>` — never re-read this file and assume it still holds.

## The defect in one paragraph

When Claude Code rotates an OAuth refresh token, it writes the new credential to the macOS keychain
by shelling out to `security(1)` with a **2 000 ms timeout**. If that subprocess times out, the
write is classified `transient: true` — and `transient` causes the credential store to **return
early, skipping the plaintext fallback it exists to fall back to**. There is no retry. Both callers
— the in-session refresh and `claude auth login` — then **report success anyway**. The new refresh
token never leaves process memory, while the authorization server has already rotated away from the
old one. The next process to read the store replays a token the server no longer honours, gets
`400 invalid_grant`, and the user is told to run `/login` for no reason they can see.

The inversion at the centre of it: **`transient` is treated as a reason to do *less*.** Everywhere
else that word means *retry* or *degrade gracefully*. Here it is the one classification that
disables the safety net — and it is assigned to precisely the failure most likely to be spurious and
recoverable (a keychain that was slow for two seconds), while a *hard* keychain failure — locked
keychain, non-zero exit — correctly falls through to plaintext and survives.

## Where it is, in the shipped bundle

All three excerpts are verbatim from `2.1.220`. Minified names are this build's; the strings are not.

**1. The write, and the classification.** `_Qt = 2000`, `Lcg = 4032`:

```js
async update(e){ iG(); try{
  let t=oG(j1e), r=_q(), n=Ie(e), o=Buffer.from(n,"utf-8").toString("hex"),
      i=`add-generic-password -U -a "${r}" -s "${t}" -X "${o}"\n`, s;
  if(i.length<=Lcg) s=await ax("security",["-i"],{input:i,stdio:["pipe","pipe","pipe"],reject:!1,timeout:_Qt});
  else w(`Keychain payload (${n.length}B JSON) exceeds security -i stdin limit; using argv`,{level:"warn"}),
       s=await ax("security",["add-generic-password","-U","-a",r,"-s",t,"-X",o],{stdio:["ignore","pipe","pipe"],reject:!1,timeout:_Qt});
  if(s.exitCode!==0) return {success:!1, transient:s.timedOut};        // ← timeout ⇒ transient:true
  return NI.cache={data:e,cachedAt:Date.now()},{success:!0}
}catch(t){ return {success:!1} } }
```

**2. The fallback that `transient` skips.** The active store is
`keychain-with-plaintext-fallback` (`zs()` returns `bFc(Q5i, XJn)`):

```js
async update(n){
  let o=await e.readAsync(), i=await e.update(n);
  if(i.success){ if(o===null) await t.delete(); return be("secure_storage_credentials_write"), i }
  if(i.transient) return Ne("secure_storage_credentials_write","primary_transient_skip_fallback"), i;   // ← returns
  let s=await t.update(n);                                              // ← never reached on a timeout
  if(s.success){ if(o!==null) await e.delete();
    return Ne("secure_storage_credentials_write","plaintext_fallback_used"), {success:!0,warning:s.warning} }
  return pe("secure_storage_credentials_write","primary_and_fallback_failed"), {success:!1}
}
```

There is **no retry** anywhere on this path. The surrounding `Hcg()` wrapper retries only the
cross-process *lock* acquisition (`retries: 10`); the write itself is attempted exactly once.

**3. Both callers discard the verdict.**

*In-session refresh* — `Wer(f)` returns `{success:false}` and the comma expression throws it away,
yielding the string `"refreshed"`, which the caller converts to `true`:

```js
return await Wer(f), wq(), "refreshed"                 // Wer's verdict evaluated, then discarded
function O_(e=0,t=!1,r){ return wno(e,t,r).then((n)=>n==="refreshed") }   // ⇒ resolves true
```

`Wer()` itself does the right thing — it captures the verdict and fires
`tengu_oauth_tokens_save_failed`. Only its caller drops it.

*`claude auth login`* — and this ordering is the destructive one. `VUt()` **deletes the stored
credential first**, then writes:

```js
async function VUt(e){
  await cht({clearOnboarding:!1, preserveInProcessTokens:!0, preserveNonAnthropicAuth:!0});
  //  └─ ...await o.mutate((i)=>{ let s={...i}; delete s.claudeAiOauth; delete s.organizationUuid;
  //                              delete s.trustedDeviceToken; ... return s }).catch(...)
  //     the wipe's own {success:false} is discarded too — .catch() only sees throws.
  ...
  nat({action:"login", success:!0, authMethod:"oauth"});     // success telemetry BEFORE the write
  let r = await Wer(e);                                      // the write
  ...
}
```

and the CLI prints its result unconditionally:

```js
await VUt(g); ... be("cli_auth_login"), process.stdout.write(`Login successful.\n`)
```

`VUt()` never throws on a failed write and its caller never inspects a return value, so
**`Login successful.` is printed and the process exits 0 with no credential on disk.**

## What each ordering leaves behind

| wipe | write | on disk afterwards | what the user is told |
|---|---|---|---|
| — | ok | new credential | correct |
| — | **times out** | the **old** refresh token, which the server has just rotated away from | `"refreshed"` / nothing |
| ok | ok | new credential | `Login successful.` |
| **ok** | **times out** | **nothing** — `claudeAiOauth` deleted, replacement only in RAM | `Login successful.`, exit 0 |

Row 2 is the daily-forced-`/login` shape: the store replays a retired token until a human
re-authenticates. Row 4 is worse and rarer: `claude auth login` reports success and leaves the
machine logged out. *(That the server retires the previous refresh token on rotation is inferred
from the observed `400`s, not from any statement about the server — see UPDATE 3, where one account
answered `400` twenty times in 95 minutes with its `refreshTokenExpiresAt` still 674 hours away.)*

One further consequence follows from the code: after a failed write `Wer()` still clears the
in-memory token caches (`ms.cache?.clear?.()`, `vB.cache?.clear?.()`), so the very next read falls
back to the store — i.e. to the credential that was just superseded. The session does not keep using
the token it successfully obtained. *(Derived from the code, not observed at runtime.)*

## Why 2 000 ms is reachable in practice

`security(1)` is a process spawn plus a keychain-daemon round trip, on a keychain that may be
contended, locked, iCloud-syncing, or under load from a fleet of concurrent sessions. Two seconds is
generous for the happy path and thin for the tail. The exposure scales with concurrency: every
session that reaches its access-token expiry rotates the *same* underlying grant, so N sessions are N
chances per rotation window for one write to land in that tail — and one loss retires the grant for
all of them.

## Suggested fixes, in the order we would take them

1. **Do not let `transient` skip the fallback.** A timed-out primary write is the case with the
   *most* to gain from a second tier, not the least. At minimum, try the plaintext fallback and
   report the warning it already carries.
2. **Retry the write once before giving up.** The write is idempotent (`-U` updates in place); the
   lock is already held; a single retry costs 2 s in the failure case and nothing otherwise.
3. **Propagate the verdict to the callers.** `Wer()` already returns it and already fires
   `tengu_oauth_tokens_save_failed`. Make `bJi()` return something other than `"refreshed"` when the
   save failed, and make `claude auth login` exit non-zero rather than print `Login successful.`
4. **Write before wiping in `VUt()`.** Only clear the previous credential once the replacement is
   durably stored. This alone turns row 4 of the table above into row 2.
5. **Raise the 2 000 ms bound**, or make it adaptive. Least important of the five — it narrows the
   window without closing it.

Fixes 1–4 are all local to the two functions above and none require a protocol change.

## Anthropic can measure this fleet-wide today; we cannot

The instrumentation is already in the binary, on both halves of the failure:

- `secure_storage_credentials_write` → `primary_transient_skip_fallback` — fires **exactly** when a
  write is lost this way.
- `tengu_oauth_tokens_save_failed` — fires with the storage-backend name on every discarded verdict.

The rate of the first counter *is* the incidence of this bug. From outside, all we can observe is the
aftermath — a `400 invalid_grant` storm hours later, indistinguishable from an ordinary expiry — which
is exactly why it read to us for weeks as "it just comes up daily, with no warning".

## Secondary finding — the credential blob can move onto `argv`

Distinct from the above and reported here because it is the *other* branch of the same `update()`.
When the constructed command exceeds `Lcg = 4032` characters, the write switches from `security -i`
(stdin) to passing the credential as an **argv parameter**:

```js
s=await ax("security",["add-generic-password","-U","-a",r,"-s",t,"-X",o], …)   //  o = hex(credentials)
```

`o` is the hex encoding of the *entire* secure-storage blob — `claudeAiOauth` plus `mcpOAuth`,
`pluginSecrets`, `gatewayTrust` and anything else in it — so the payload grows with every MCP server
and plugin the user authenticates. On macOS that argv is readable via `ps` by the same user and is
captured by process-accounting and EDR agents. The code knows this is a compromise (it logs a
warning) but takes it silently from the user's perspective.

**Measured on this machine, 2026-08-08** — every Claude Code config directory, JSON size → resulting
command length, against the 4 032 threshold:

| config dir | blob (JSON) | command chars | vs. threshold |
|---|---:|---:|---|
| `.claude` | 775 B | ≈ 1 610 | under |
| `.claude-next` | 1 713 B | ≈ 3 486 | under |
| `.claude-tertiary` | 1 713 B | ≈ 3 486 | under |
| `.claude-secondary` | **1 923 B** | **≈ 3 906** | **126 characters below it** |

So the argv branch is **not currently reached here** — stated plainly because it would be easy to
present this as a live exposure and it is not. It is one MCP token away from being one, on an account
that already exists, and nothing in the product bounds the blob's growth.

## Re-checking this report against a newer build

```
scripts/cc-authstore-probe.sh <path-to-claude-binary>
```

Reads the candidate bundle (never executes it) and exits `0 FIXED` · `1 STATUS-QUO` · `2 WORSE`
(the plaintext tier was removed) · `3 UNREADABLE` (anchors no longer resolve — re-derive them). It
resolves the two constants from the candidate's own use-sites rather than trusting the values above,
so a version that merely moves them is reported accurately. The same probe runs as check #14 of
`scripts/cc-upgrade-gate.sh`, where `STATUS-QUO` deliberately **SKIP**s: an upstream defect we cannot
fix, unchanged from the binary we already run, is not grounds to refuse an upgrade — but `WORSE` and
`UNREADABLE` fail the gate, and `FIXED` is the signal to close backlog item `4adbeab56aa7` and
revisit the compensating machinery landed in `f8178bfe`.
