# A wrapper renames your own timeout into a foreign fault

**The rule.** When you bound a call with your own clock, classify its failure by walking the
**cause chain**, not the top-level error. A client library that wraps provider failures in its own
error type will re-label *your* `AbortSignal` expiring as *its* transport error — so the one
failure you fully control arrives looking like someone else's, and every minute you spend
debugging goes to the wrong system.

## The incident (2026-09-19, claude-infrastructure)

`scripts/jev/evaluate.mjs` bounds one Vercel AI Gateway call with `AbortSignal.timeout(TIMEOUT_MS)`
and classifies the catch into a small set of abstain reasons. The timeout arm read:

```js
const name = e?.name || '';
const msg  = String(e?.message || e);
if (name === 'TimeoutError' || name === 'AbortError' || /abort|timed? ?out/i.test(msg))
  abstain('timeout');
```

That is correct for a bare fetch. It is wrong here, because `@ai-sdk/gateway` catches everything in
`doEvaluate` and re-throws through `asGatewayError(...)`. What arrived was a **`GatewayError`
subclass** whose message said nothing about aborting. The chain fell through to the default arm and
emitted:

```json
{"ok":false,"reason":"http","ms":1515}
```

`1515` against a `CC_JEV_TIMEOUT_MS` of **1500**. The number was sitting in the output the whole
time, one field away from the misclassification.

**What it cost.** `reason: "http"` is a statement about the *network*, so that is where the
investigation went: the egress allowlist was re-checked, the CONNECT proxy was re-read, the key
length was re-verified, and a standalone diagnostic was written to surface the real error. All of
it was fine. The actual finding — steady state is 742–791 ms and the *first* call through a cold
proxy takes ~1515 ms, so the 1500 ms default was never the 2× headroom it looked like — was
reachable from `ms: 1515` alone.

## The fix

```js
const chain = [];
for (let c = e, i = 0; c && i < 5; c = c.cause, i++) chain.push(c);
const name = chain.map((c) => c?.name || '').join(' ');
const msg  = chain.map((c) => String(c?.message || '')).join(' ');
if (/TimeoutError|AbortError/.test(name) || /abort|timed? ?out|signal is aborted/i.test(msg))
  abstain('timeout');
```

Bounded at 5 hops so a cyclic `cause` cannot spin.

## Why this generalises past one SDK

Any layer that owns error presentation does this: an HTTP client, an ORM, a retry wrapper, a
message-bus consumer, a gateway SDK. The asymmetry is what makes it expensive — **a foreign fault
is a claim about someone else's system, and it is believed**, exactly like
`reference-a-refusal-bounds-the-tool-not-the-world`. A self-inflicted fault mislabelled as a
foreign one does not merely lose information; it points the next hour away from the cause.

**The test that catches it** is not a mock — a mock returns whatever shape you wrote. Force the
real client to breach a deliberately tiny budget and assert on the emitted *reason*:

```
CC_JEV_TIMEOUT_MS=200 … | jev_ask     # must say reason=timeout, never reason=http
```

## Companions

- `predicate-error-exit-is-indistinguishable-from-false` — the same collapse one layer down.
- `null-result-must-not-use-the-error-channel` — why abstain classes must stay distinguishable.
- `parse-failures-are-verdicts-not-noise`.
