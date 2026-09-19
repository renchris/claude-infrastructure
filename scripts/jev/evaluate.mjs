#!/usr/bin/env node
// evaluate.mjs — ONE Jev evaluation call, shaped for a Stop-hook caller.
//
// WHY THIS EXISTS. A Claude Code hook cannot spend a Claude turn, so every semantic
// judgment in the hook layer is served today by a regex. Two of them are MEASURED wrong:
// anti-deference-nudge abstains `no-tell` on 94.7% of its 5,398 evaluations, and
// completion-assert's kill-switch arm matched 29 messages of which 26 were machine-authored.
// Jev (typesafe-ai/jev, evaluation modality) answers typed questions with probabilities in
// one round trip, which is the one thing at-cost API buys that plan usage structurally cannot.
// Full case + the refutations it survived: docs/research/jev-at-cost-api-2026-09-18.md.
//
// THE CONTRACT, and every clause of it is load-bearing:
//
//   stdin   one JSON object {state, questions} — the AI SDK's own evaluate() shape.
//   stdout  exactly one JSON object, always. Never the state, never the key.
//   exit 0  ANSWERED  → {ok:true, answers, usage, ms}
//   exit 10 ABSTAIN   → {ok:false, reason, ms}   ← "no opinion". NOT false, NOT an error.
//   exit 2  BAD SPEC  → {ok:false, reason:"bad-spec", detail}  ← the caller is wrong, not the net.
//
// 🚨 ABSTAIN HAS ITS OWN EXIT CODE ON PURPOSE. The repo has two standing lessons about exactly
// this: `null-result-must-not-use-the-error-channel` (an acquit-only producer that says "nothing"
// on the error channel mints false greens downstream) and `predicate-error-exit-is-indistinguish-
// able-from-false` (a predicate fed the wrong object type exits non-zero and `||` reads it as a
// clean "no" — 20 of 20 rows lied). A network failure and "Jev says false" MUST NOT share a code.
//
// 🚨 NO RETRIES BY DEFAULT. The SDK defaults maxRetries to 2; in a hook that turns one bounded
// wait into three (`bounding-external-calls`: a per-fork bound MULTIPLIES across a retry loop).
// The caller owns the wall clock, so the wall clock is one timeout over one attempt.
//
// 🚨 ZDR IS ON BY DEFAULT AND FAILS CLOSED. providerOptions.gateway.zeroDataRetention routes only
// through providers holding a zero-retention agreement, and errors outright when none is available
// rather than silently downgrading. That polarity is why this is safe to point at prose the model
// wrote; it is NOT a licence to send private corpora (see cc-jev's REDACTION note).

import { readFileSync, writeSync } from 'node:fs';

const t0 = process.hrtime.bigint();
const ms = () => Number(process.hrtime.bigint() - t0) / 1e6;

/** Emit the single stdout object and leave. `code` is the contract above, never a guess.
 *  writeSync, NOT process.stdout.write: writes to a PIPE are async, and process.exit() can
 *  truncate one mid-flight. The caller is a bash hook reading this over a pipe, and an empty
 *  read there is indistinguishable from a verdict (`killed-pipeline-empty-output-is-not-a-
 *  verdict`). A guaranteed byte is worth the syscall. */
const out = (code, body) => {
  writeSync(1, JSON.stringify({ ...body, ms: Math.round(ms()) }) + '\n');
  process.exit(code);
};
const abstain = (reason) => out(10, { ok: false, reason });

const MODEL = process.env.CC_JEV_MODEL || 'typesafe-ai/jev';
// 2500 ms, MEASURED not guessed. The real path is agent-secrets (~230 ms) + a loopback CONNECT
// proxy + the round trip, and steady state on this box is 742-791 ms. 1500 ms looked like 2x
// headroom and was not: the FIRST call through a cold proxy took 1515 ms and abstained. An
// abstain is safe — it falls through to the caller's existing path — but one that fires on every
// cold start makes the arm useless at exactly the moment a session begins.
const TIMEOUT_MS = Number(process.env.CC_JEV_TIMEOUT_MS || 2500);
const ZDR = process.env.CC_JEV_ZDR !== '0';

if (!process.env.AI_GATEWAY_API_KEY) abstain('no-key');

let spec;
try {
  spec = JSON.parse(readFileSync(0, 'utf8'));
} catch {
  out(2, { ok: false, reason: 'bad-spec', detail: 'stdin is not JSON' });
}
if (!spec || typeof spec !== 'object' || spec.state === undefined || !spec.questions) {
  out(2, { ok: false, reason: 'bad-spec', detail: 'need {state, questions}' });
}
if (Object.keys(spec.questions).length === 0) {
  out(2, { ok: false, reason: 'bad-spec', detail: 'questions is empty' });
}

// Imported only after the cheap rejections above, so a keyless or malformed call never pays
// the module load. Measured on this box: node boot + `import('ai')` is ~80-130 ms total.
let evaluate;
let model = MODEL;
try {
  ({ experimental_evaluate: evaluate } = await import('ai'));
  // CC_JEV_BASE_URL is the TEST SEAM, and it is the only way this file is verifiable without a
  // paid key: a bare model-id string resolves through the default provider and can only ever
  // talk to ai-gateway.vercel.sh. tests/jev-evaluate.bats points it at a local mock built to the
  // gateway's own response schema. It is unset in every real invocation.
  if (process.env.CC_JEV_BASE_URL) {
    const { createGateway } = await import('@ai-sdk/gateway');
    model = createGateway({
      baseURL: process.env.CC_JEV_BASE_URL,
      apiKey: process.env.AI_GATEWAY_API_KEY,
    }).evaluationModel(MODEL);
  }
} catch {
  abstain('deps-missing');
}

// One attempt, one clock. AbortSignal.timeout covers connect + TLS + body — an inner provider
// timeout would miss the connect phase, which is the half that actually hangs on a dead network.
try {
  const r = await evaluate({
    model,
    state: spec.state,
    questions: spec.questions,
    maxRetries: 0,
    abortSignal: AbortSignal.timeout(TIMEOUT_MS),
    ...(ZDR ? { providerOptions: { gateway: { zeroDataRetention: true } } } : {}),
  });
  out(0, {
    ok: true,
    answers: r.answers,
    usage: r.usage,
    // `warnings` is always present on the result type; a non-empty one means the provider
    // silently altered the request, which a caller thresholding on probability must see.
    warnings: (r.warnings ?? []).map((w) => w.type ?? String(w)),
  });
} catch (e) {
  // Classify, never collapse. A caller that cannot tell `no-key` from `timeout` cannot tell a
  // misconfiguration it should fix from a network blip it should ignore.
  // Walk the CAUSE CHAIN, not just the top error. The gateway wraps a provider failure in its own
  // GatewayError, so an AbortSignal timeout arrives with a Gateway name and a message that says
  // nothing about aborting — and the first draft duly classified a timeout of MY OWN budget as
  // `http`. That reason sent this session hunting a network fault for a value it had itself set.
  // A classifier that cannot see its own timeout is worse than one that does not classify.
  const chain = [];
  for (let c = e, i = 0; c && i < 5; c = c.cause, i++) chain.push(c);
  const name = chain.map((c) => c?.name || '').join(' ');
  const msg = chain.map((c) => String(c?.message || '')).join(' ');
  if (/TimeoutError|AbortError/.test(name) || /abort|timed? ?out|signal is aborted/i.test(msg)) abstain('timeout');
  if (/LoadAPIKey|API key/i.test(name + msg)) abstain('no-key');
  if (/UnsupportedQuestionType/i.test(name)) out(2, { ok: false, reason: 'unsupported-question', detail: msg.slice(0, 200) });
  if (/InvalidArgument|InvalidPrompt/i.test(name)) out(2, { ok: false, reason: 'bad-spec', detail: msg.slice(0, 200) });
  if (/InvalidResponseData|TypeValidation/i.test(name)) abstain('invalid-response');
  if (/NoSuchModel|NoSuchProvider/i.test(name)) abstain('no-model');
  // 429 gets its OWN reason. "Free until 2026-09-25" is free PRICING, not free THROUGHPUT — the
  // gateway rate-limits free-tier requests on this model, and a caller that cannot tell a rate
  // limit from a server fault will read a self-inflicted burst as a broken route. It is also the
  // one abstain class where the right response is to SLOW DOWN rather than to give up.
  if (/RateLimit/i.test(name) || /rate.?limit/i.test(msg)) abstain('rate-limited');
  abstain('http');
}
