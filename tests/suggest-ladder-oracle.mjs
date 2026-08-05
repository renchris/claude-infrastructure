// suggest-ladder-oracle.mjs — run Claude Code's REAL prompt-suggestion content filter.
//
// WHY: bin/cc-suggest-filter re-implements the 12-rule ladder (`TM_`) in Python so the measurement
// needs no node and no binary. A re-implementation that is only checked against its own fixtures is
// checked against nothing (memory: control-must-replay-the-real-artifact) — and the JS->Python
// regex traps here are real, not hypothetical: JS `$` is end-of-input while Python `$` also matches
// before a trailing newline, and JS `\w` is ASCII while Python's is Unicode.
//
// So this oracle EXECUTES the ladder source extracted verbatim from the installed binary
// (`cc-suggest-filter ladder-source`) and emits its verdicts. tests/suggest-filter.bats asserts the
// two agree verdict-for-verdict over the same corpus. Nothing here re-states a rule; if this file
// and the ladder ever disagree, the ladder is right by construction.
//
// Usage:  node suggest-ladder-oracle.mjs <ladder-source-file>   < JSONL{text} > JSONL{text,reason}
// Exit:   0 verdicts produced · 2 usage · 3 the source does not define TM_ (NO DATA, not a failure)

import { readFileSync } from "node:fs";

const path = process.argv[2];
if (!path) {
  process.stderr.write("usage: suggest-ladder-oracle.mjs <ladder-source-file> < JSONL\n");
  process.exit(2);
}

const src = readFileSync(path, "utf8");

// `TM_` calls `HY(reason, text, source)` for its side effect and returns true when it rejects. We
// supply HY as the sole free variable, so the captured argument IS the `reason` the suppression
// telemetry would have carried — not an interpretation of one.
let captured = null;
let TM_;
try {
  TM_ = new Function("HY", `${src}\n;return TM_;`)((reason) => {
    captured = reason;
  });
} catch (e) {
  process.stderr.write(`oracle: ladder source did not evaluate: ${e.message}\n`);
  process.exit(3);
}
if (typeof TM_ !== "function") {
  process.stderr.write("oracle: ladder source does not define TM_\n");
  process.exit(3);
}

const input = readFileSync(0, "utf8");
let n = 0;
for (const line of input.split("\n")) {
  const trimmed = line.trim();
  if (!trimmed) continue;
  let row;
  try {
    row = JSON.parse(trimmed);
  } catch {
    continue;
  }
  captured = null;
  const rejected = TM_(row.text ?? "", "cli");
  row.reason = rejected ? captured : "pass";
  process.stdout.write(`${JSON.stringify(row)}\n`);
  n += 1;
}
process.exit(n ? 0 : 3);
