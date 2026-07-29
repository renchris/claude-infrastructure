#!/usr/bin/env bun
// Format ONLY -- no organize-imports plugin. That plugin strips imports it thinks are unused,
// which breaks split edits (add import -> use it in the next edit). Run the destructive rules
// at CI instead, so imports still get cleaned up before merge.
// GENERAL RULE: idempotent-safe rules in the hook, destructive rules at CI only.
const input = await Bun.stdin.json();
const file = input?.tool_input?.file_path ?? "";
if (!/\.(ts|tsx|js|jsx|mjs|cjs|json|css|md|yaml|yml)$/.test(file)) process.exit(0);
Bun.spawnSync(["./node_modules/.bin/prettier", "--config", ".prettierrc", "--write", file]);
