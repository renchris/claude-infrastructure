#!/usr/bin/env node
// jev-mock-gateway.mjs — a local stand-in for POST {baseURL}/evaluation-model.
//
// Built to the SHAPE @ai-sdk/gateway's own client actually sends and parses (read out of
// node_modules/@ai-sdk/gateway/dist/index.js `GatewayEvaluationModel.doEvaluate`): the request
// body is {state, questions, providerOptions?} and the response is
// {answers, rounding?, usage?, warnings?, providerMetadata?}.
//
// 🚨 WHAT THIS DOES AND DOES NOT PROVE. It verifies OUR half end to end — request assembly,
// ZDR propagation, answer parsing, and every branch of the exit-code contract — without a paid
// key. It does NOT verify Jev's real behaviour, wire quirks, or accuracy; no Jev call has been
// made from this machine. Treat a green run here as "the plumbing is correct", never as
// "Jev works for this task" (docs/research/jev-at-cost-api-2026-09-18.md §5).
//
// MODE (argv[2]): ok | lowp | slow | err500 | err401 | garbage
import { createServer } from 'node:http';
import { writeFileSync } from 'node:fs';

const mode = process.argv[2] || 'ok';
const server = createServer((req, res) => {
  let raw = '';
  req.on('data', (c) => (raw += c));
  req.on('end', () => {
    if (mode === 'slow') return;                       // never answers: exercises the caller's clock
    if (mode === 'err500') { res.writeHead(500, {'content-type':'application/json'}); return res.end('{"error":{"message":"upstream boom"}}'); }
    if (mode === 'err401') { res.writeHead(401, {'content-type':'application/json'}); return res.end('{"error":{"message":"invalid api key"}}'); }
    if (mode === 'garbage') { res.writeHead(200, {'content-type':'application/json'}); return res.end('{"answers":{"q":{"type":"nonsense"}}}'); }

    const body = JSON.parse(raw || '{}');
    // Echo what was SENT to a side file. Asserting only on what came back would leave ZDR
    // propagation — the clause that makes this safe to point at model prose — unverified.
    if (process.env.MOCK_ECHO) writeFileSync(process.env.MOCK_ECHO, JSON.stringify(body));

    const answers = {};
    for (const [id, q] of Object.entries(body.questions || {})) {
      if (q.type === 'boolean') {
        // `lowp` is the ABSTAIN-BAND arm: 0.40 is a real answer that must NOT cross
        // CC_JEV_MIN_P. Without it the suite could only ever prove the firing direction.
        // Both values are chosen against Jev's MEASURED range, deliberately far from any
        // plausible gate — a fixture picked as "just under the default" re-derives itself
        // when the default moves and can only ever confirm it (docs/lessons/
        // an-imported-threshold-can-sit-above-the-model-s-output-range.md).
        answers[id] = { type: 'boolean', probability: mode === 'lowp' ? 0.40 : 0.99 };
      } else if (q.type === 'choice') {
        // MOCK_CHOICE steers the choice answer. Without it the mock would always return the
        // FIRST criteria key, which for the anti-deference arm is "none" — so every firing test
        // would pass for the wrong reason (silence) and the suite could never exercise the fire
        // path at all. A fixture that can only produce one branch is a vacuous control.
        const keys = Object.keys(q.criteria);
        const want = process.env.MOCK_CHOICE;
        const pick = want && keys.includes(want) ? want : keys[0];
        answers[id] = { type: 'choice', choice: pick, probabilities: Object.fromEntries(keys.map((k) => [k, k === pick ? 1 : 0])) };
      } else {
        const top = q.criteria.length - 1;
        answers[id] = { type: 'score', score: top, probabilities: { [String(top)]: 1 } };
      }
    }
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ answers, usage: { inputTokens: 283, outputTokens: 21 }, warnings: [] }));
  });
});
server.listen(0, '127.0.0.1', () => process.stdout.write(String(server.address().port) + '\n'));
