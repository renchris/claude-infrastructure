import { describe, expect, test } from "claude-code/testing";

const SPAWN = {
  tool_use_id: "tu1", prompt: "do it", description: "probe task", subagentType: "general-purpose",
  provider: { plugin: "engine", tier: "core" }, parentModel: "claude-opus-5-5", background: true, fork: false,
} as any;

function stubs(on: any, state: { tokens: number; written?: any }) {
  let n = 0;
  on("session.usage", () => ({ value: { startedAt: 0, rateLimits: [], context: { tokens: state.tokens, window: 200_000 } } }));
  on("env.get", () => ({ value: undefined }));
  on("session.cwd", () => ({ value: "/work" }));
  on("session.id", () => ({ value: "s1" }));
  on("fs.write", ($: any, e: any) => { state.written = e; return { value: undefined }; });
  on("agent.spawn", () => ({ model: "claude-opus-5-5", agentId: `a${++n}` }));
  on("turn.complete", () => ({ text: "" }));
  on("prompt.submit", ($: any, e: any) => ({ text: e.text }));
}

describe("spawn-governor", () => {
  test("refuses a spawn once fill plus outstanding returns crosses the limit, re-admits after delivery", async ($, on) => {
    const s = { tokens: 140_000 };
    stubs(on, s);
    const first = await $.agent.spawn(SPAWN);
    expect(first.agentId).toBe("a1");                         // 140k + 6k = 73%
    const second = await $.agent.spawn({ ...SPAWN, tool_use_id: "tu2" });
    expect(second.deny).toMatch(/1 agent return\(s\) are still outstanding/); // 140k + 6k + 6k = 76%
    await $.turn.complete({ reason: "answer", answer: "short", durationMs: 1, isAborted: false, turnId: "t", agentId: "a1" } as any);
    await $.prompt.submit({ text: "<task-notification><task-id>a1</task-id>done</task-notification>", wait: false, origin: { kind: "task-notification" } } as any);
    const third = await $.agent.spawn({ ...SPAWN, tool_use_id: "tu3" });
    expect(third.agentId).toBe("a2");
  });

  test("exact depth from parentAgentId: depth 3 is refused under the default cap of 2", async ($, on) => {
    stubs(on, { tokens: 10_000 });
    const lead = await $.agent.spawn(SPAWN);                                       // a1, depth 1
    const child = await $.agent.spawn({ ...SPAWN, parentAgentId: lead.agentId });  // a2, depth 2
    expect(child.agentId).toBe("a2");
    const grandchild = await $.agent.spawn({ ...SPAWN, parentAgentId: child.agentId });
    expect(grandchild.deny).toMatch(/depth 3, cap 2/);
  });

  test("an oversized foreground Agent return is capped and spilled to a file", async ($, on) => {
    const s: { tokens: number; written?: any } = { tokens: 10_000 };
    stubs(on, s);
    const big = "x".repeat(20_000);
    on("tool.call", () => ({
      result: {
        status: "completed", agentId: "a9", prompt: "p", content: [{ type: "text", text: big }],
        totalToolUseCount: 0, totalDurationMs: 1, totalTokens: 1,
        usage: { input_tokens: 1, output_tokens: 1, cache_creation_input_tokens: null, cache_read_input_tokens: null, server_tool_use: null, service_tier: null, cache_creation: null },
      },
    }));
    const r: any = await $.tool.call({ tool: "Agent", description: "big", prompt: "p", run_in_background: false } as any);
    const text = r.result.content[0].text;
    expect(text.length < 2_300).toBe(true);
    expect(text).toMatch(/\/work\/\.claude\/agent-returns\/s1\/a9\.md/);
    expect(s.written.text.length).toBe(20_000);
  });
});
