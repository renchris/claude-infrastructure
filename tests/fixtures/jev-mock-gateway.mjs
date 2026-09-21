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
// MOCK_CHOICE_ROTATE=1 walks each choice question through its OWN criteria keys, one per request.
// It exists because every other knob here is CONSTANT across a run, so a consumer that reports on
// the SPREAD of its answers (cc-jev rank's rubric-discrimination section) could only ever be shown
// the flat case — and its "discriminates" branch would ship having never executed. Per-question
// counters, because two questions in one request must advance independently.
const rotate = process.env.MOCK_CHOICE_ROTATE === '1';
const rotN = Object.create(null);
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
        // Steering is PER-QUESTION first (MOCK_CHOICE_<ID>), then global (MOCK_CHOICE). The
        // per-question form exists because a consumer may ask two choice questions over DISJOINT
        // key sets in one call — `cc-jev rank` asks `bite` and `breadth`. Under the global-only
        // form, a value naming a bite level matches bite and silently falls through to keys[0]
        // for breadth, so any assertion on breadth passes for the wrong reason (the default) and
        // that branch is never exercised. Same defect this block's own comment already names one
        // question up: a fixture that can only produce one branch is a vacuous control.
        const keys = Object.keys(q.criteria);
        const want = process.env['MOCK_CHOICE_' + id.toUpperCase()] || process.env.MOCK_CHOICE;
        let pick;
        if (rotate) { const i = (rotN[id] = (rotN[id] === undefined ? 0 : rotN[id] + 1)); pick = keys[i % keys.length]; }
        else { pick = want && keys.includes(want) ? want : keys[0]; }
        answers[id] = { type: 'choice', choice: pick, probabilities: Object.fromEntries(keys.map((k) => [k, k === pick ? 1 : 0])) };
      } else {
        // MOCK_SCORE steers the ordinal, for the same reason MOCK_CHOICE steers the choice: without
        // it this branch can only ever return the TOP level, so any consumer that RANKS on the
        // score sees one value for every input and its sort is untested — a fixture that can only
        // produce one branch is a vacuous control. Read as an INDEX into criteria (which is what
        // the gateway returns — a level, never the label text), clamped so a bad value cannot
        // silently become the top again.
        const top = q.criteria.length - 1;
        const want = Number(process.env.MOCK_SCORE);
        const pick = Number.isInteger(want) && want >= 0 && want <= top ? want : top;
        answers[id] = { type: 'score', score: pick, probabilities: { [String(pick)]: 1 } };
      }
    }
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ answers, usage: { inputTokens: 283, outputTokens: 21 }, warnings: [] }));
  });
});
server.listen(0, '127.0.0.1', () => process.stdout.write(String(server.address().port) + '\n'));
