#!/usr/bin/env bun
// Deterministic enforcement. Bun added these hooks 2025-10-04 "to prevent common development
// mistakes" -- i.e. PROSE ALONE DEMONSTRABLY FAILED to constrain the model.
//
// The load-bearing idea, and the reason a naive guard does not work: a model will append ` 2>&1`
// or pipe the command to evade a raw string match. Bun's own source carries the comment
// `// Claude is a sneaky fucker` immediately above ~30 lines of exactly this normalization.
// NORMALIZE TO ARGV SEMANTICS BEFORE DECIDING.
const input = await Bun.stdin.json();
const raw = input?.tool_input?.command ?? "";

let toks = raw.trim().split(/\s+/);
const pipeAt = toks.indexOf("|");
if (pipeAt >= 0) toks = toks.slice(0, pipeAt);              // drop everything after a pipe
toks = toks.filter((t) => !/^(2>&1|1>&2|>>?|>\S+)$/.test(t)); // drop redirections
const env = {};
while (toks.length && /^[A-Z_][A-Z0-9_]*=/.test(toks[0])) {   // lift inline FOO=1 assignments
  const [k, ...v] = toks.shift().split("=");
  env[k] = v.join("=");
}
const [cmd, ...args] = toks;

const deny = (r) => (
  console.log(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: r,
    },
  })), process.exit(0)
);

// Adapt these to your project. The shapes matter more than the specifics:
// (1) forbid the command that silently tests the WRONG binary,
// (2) forbid the whole-suite run that wastes an hour,
// (3) forbid a timeout wrapper that truncates a long build into a false failure.
if (cmd === "run-tests" && env.USE_SYSTEM_BIN !== "1")
  deny("error: In development, use `build && run-tests <file>` to test your changes");
if (args[0] === "test" && args.length === 1)
  deny("will run all tests. Use `run-tests <path>` with a specific test file.");
if (cmd === "timeout" && args.includes("build"))
  deny("error: Run `build` without a timeout");

process.exit(0);
