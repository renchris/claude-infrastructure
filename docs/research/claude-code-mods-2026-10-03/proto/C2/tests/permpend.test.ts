import { describe, expect, mock, test } from "claude-code/testing";

const PR = (cmd: string) => ({ hook_event_name: "PermissionRequest", session_id: "sid-1", cwd: "/work",
  transcript_path: "/t.jsonl", tool_name: "Bash", tool_input: { command: cmd } }) as any;

function harness(on: any, env: Record<string, string>) {
  const writes: Record<string, string> = {};
  const runs: string[][] = [];
  let seenId = "";
  let release: () => void = () => {};
  const gate = new Promise<void>((r) => (release = r));
  let started: () => void = () => {};
  const inFlight = new Promise<void>((r) => (started = r));
  mock.env(on, env);
  on("fs.write", ($: any, e: any) => { writes[e.path] = e.text; return { value: undefined }; });
  on("process.run", ($: any, e: any) => { runs.push([...e.argv]); return { value: { exitCode: 0, stdout: "", stderr: "" } }; });
  on("tool.check", () => ({ decision: "ask", reason: "matches ask rule", rule: "Bash(git push:*)" }));
  on("classic.PermissionRequest", () => ({}));
  on("tool.call", async ($: any, e: any) => { seenId = e.tool_use_id; started(); await gate; return { result: "ok" }; });
  return { writes, runs, id: () => seenId, release: () => release(), inFlight };
}

describe("fleet-permpend", () => {
  test("beacon names the gated call and clears only when that call resolves", async ($, on) => {
    const h = harness(on, { CC_PERMPEND_DIR: "/pp", CC_PERMARCHIVE_DIR: "/arch", HOME: "/h" });
    const call = $.tool.call({ tool: "Bash", command: "git push --force" } as any);
    await h.inFlight;
    const id = h.id();
    expect(id).toMatch(/^.+$/);
    const v = await $.tool.check({ tool: "Bash", input: { command: "git push --force" }, tool_use_id: id } as any);
    expect(v.decision).toBe("ask");
    await $.classic.PermissionRequest(PR("git push --force"));

    const tmp = Object.keys(h.writes).find((p) => p.startsWith("/pp/.sid-1."))!;
    expect(tmp).toBeDefined();
    const beacon = JSON.parse(h.writes[tmp]);
    expect(beacon.tool_use_id).toBe(id);
    expect(beacon.tool_input).toEqual({ command: "git push --force" });
    expect(h.runs).toContainEqual(["/bin/mv", "-f", tmp, "/pp/sid-1.json"]);
    expect(h.runs.find((a) => a[0] === "/bin/rm")).toBeUndefined();   // still pending: not cleared

    h.release();
    await call;
    expect(h.runs).toContainEqual(["/bin/rm", "-f", "/pp/sid-1.json"]);
    const row = Object.entries(h.writes).find(([p]) => p.startsWith("/arch/") && p.endsWith(".jsonl"))!;
    expect(row).toBeDefined();
    const r = JSON.parse(row[1]);
    expect(r).toMatchObject({ tool_use_id: id, cleared_tool_use_id: id, outcome: "ran",
      check_rule: "Bash(git push:*)", check_reason: "matches ask rule", resolved_by: "mod:tool.call" });
  });

  test("CC_UNATTENDED=1 answers the prompt with a cc-backlog deny and writes no beacon", async ($, on) => {
    const h = harness(on, { CC_PERMPEND_DIR: "/pp", CC_PERMARCHIVE_DIR: "/arch", HOME: "/h", CC_UNATTENDED: "1" });
    const call = $.tool.call({ tool: "Bash", command: "git push --force" } as any);
    await h.inFlight;
    await $.tool.check({ tool: "Bash", input: { command: "git push --force" }, tool_use_id: h.id() } as any);
    const ans: any = await $.classic.PermissionRequest(PR("git push --force"));
    expect(ans.decision.behavior).toBe("deny");
    expect(ans.decision.message).toMatch(/cc-backlog needs/);
    expect(ans.decision.message).toMatch(/Bash\(git push:\*\)/);
    expect(h.runs.find((a) => a[0] === "/bin/mv")).toBeUndefined();
    h.release();
    await call;
    const row = Object.entries(h.writes).find(([p]) => p.startsWith("/arch/"))!;
    expect(JSON.parse(row[1]).auto_denied).toBe(true);
  });
});
