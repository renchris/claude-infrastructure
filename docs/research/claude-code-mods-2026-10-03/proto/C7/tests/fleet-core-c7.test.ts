import { describe, expect, test } from "claude-code/testing";

const spawnInput = (name: string) => ({
  tool_use_id: `tu-${name}`, prompt: "work", description: `${name} task`, subagentType: "teammate",
  provider: { plugin: "engine", tier: "core" }, parentModel: "opus", background: true, fork: false,
  isTeammate: true, name,
}) as any;

function stubs(on: any, git: { porcelain: string }, writes: Record<string, string>) {
  on("clock.now", () => ({ value: 1000 }));
  on("session.id", () => ({ value: "sess-1" }));
  on("env.get", ($: any, e: any) => ({ value: e.name === "CLAUDE_CONFIG_DIR" ? "/cfg" : undefined }));
  on("fs.write", ($: any, e: any) => { writes[e.path] = e.text; return { value: undefined }; });
  on("process.run", () => ({ value: { exitCode: 0, stdout: git.porcelain, stderr: "",
    isStdoutTruncated: false, isStderrTruncated: false } }));
  on("agent.spawn", ($: any, e: any) => ({ model: "opus", agentId: `ag-${e.name}`, teammateId: `${e.name}@session-t` }));
  on("agent.list", () => ({ value: [
    { id: "ag-alpha", teammateId: "alpha@session-t", name: "alpha", description: "alpha task", type: "teammate", status: "idle" },
    { id: "ag-beta", teammateId: "beta@session-t", name: "beta", description: "beta task", type: "teammate", status: "running" },
    { id: "ag-bg", description: "bg scan", type: "Explore", status: "running" },
  ] }));
  on("classic.TeammateIdle", () => ({}));
  on("classic.Stop", () => ({}));
}

describe("fleet-core-c7", () => {
  test("blocks the lead's stop once, naming idle teammates, and exports the roster", async ($, on) => {
    const writes: Record<string, string> = {};
    stubs(on, { porcelain: "" }, writes);
    const a = await $.agent.spawn(spawnInput("alpha"));
    expect(a.teammateId).toBe("alpha@session-t");
    await $.agent.spawn(spawnInput("beta"));
    await $.classic.TeammateIdle({ teammate_name: "alpha", team_name: "session-t" } as any);

    const first = await $.classic.Stop({ stop_hook_active: false } as any);
    expect(first.block).toMatch(/alpha \(alpha@session-t\)/);
    expect(first.block).toMatch(/shutdown_request/);
    expect(first.block).toMatch(/Still running \(not blocking on these\): beta/);

    const second = await $.classic.Stop({ stop_hook_active: false } as any);
    expect(second.block).toBeUndefined();

    const doc = JSON.parse(writes["/cfg/fleet-core/roster-sess-1.json"]);
    expect(doc.residentMine).toEqual(["alpha", "beta"]);
    expect(doc.members).toHaveLength(2);
  });

  test("does not block while the lead's own tree is dirty, or inside a teammate loop", async ($, on) => {
    const writes: Record<string, string> = {};
    const git = { porcelain: " M src/app.ts\n" };
    stubs(on, git, writes);
    const dirty = await $.classic.Stop({ stop_hook_active: false } as any);
    expect(dirty.block).toBeUndefined();
    const inTeammate = await $.classic.Stop({ stop_hook_active: false, agent_id: "ag-alpha" } as any);
    expect(inTeammate.block).toBeUndefined();
    git.porcelain = "";
    const clean = await $.classic.Stop({ stop_hook_active: false } as any);
    expect(clean.block).toMatch(/alpha/);
  });
});
