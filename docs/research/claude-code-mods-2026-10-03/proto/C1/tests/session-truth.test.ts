import { describe, expect, mock, test } from "claude-code/testing";

describe("session-truth", () => {
  test("the file follows phase, engagement, measure and roster", async ($, on) => {
    mock.clock(on, { now: 1000 });
    mock.env(on, { CC_SESSION_TRUTH_DIR: "/truth" });
    const files = new Map<string, string>();
    const argvs: string[][] = [];
    on("fs.write", ($, e) => { files.set(e.path, e.text); return { value: undefined }; });
    on("process.run", ($, e) => {
      argvs.push([...e.argv]);
      const [, , from, to] = e.argv;
      files.set(to!, files.get(from!)!);
      files.delete(from!);
      return { value: { exitCode: 0, stdout: "", stderr: "", isStdoutTruncated: false, isStderrTruncated: false } };
    });
    let agents: any[] = [];
    on("session.id", () => ({ value: "sess-1" }));
    on("agent.list", () => ({ value: agents }));
    on("session.start", ($, e) => ({ cwd: e.cwd }));
    on("turn.start", ($, e) => ({ turnId: e.turnId }));
    on("turn.complete", () => ({ text: "" }));
    on("session.measure", ($, e) => ({ changed: e.changed }));
    on("agent.spawn", () => ({ model: "haiku", agentId: "a1" }));
    on("session.end", ($, e) => ({ sessionId: e.sessionId }));

    const read = () => JSON.parse(files.get("/truth/sess-1.json")!);

    await $.session.start({ surface: null, isInteractive: false, cwd: "/work" } as any);
    expect(read()).toMatchObject({ phase: "starting", sessionId: "sess-1", cwd: "/work", isInteractive: false });

    await $.turn.start({ text: "hi", turnId: "t1" } as any);
    expect(read().phase).toBe("working");

    agents = [{ id: "a1", type: "Explore", description: "scan", status: "running" }];
    await $.agent.spawn({ tool_use_id: "tu1", prompt: "p", description: "scan", subagentType: "Explore",
      provider: { plugin: "engine", tier: "core" }, parentModel: "opus", background: true, fork: false } as any);
    expect(read().agents).toEqual([{ id: "a1", type: "Explore", status: "running" }]);

    // A subagent's turn ends: roster refreshes, main phase stays working.
    agents = [{ id: "a1", type: "Explore", description: "scan", status: "completed" }];
    await $.turn.complete({ reason: "answer", answer: "found", durationMs: 5, isAborted: false, turnId: "s1", agentId: "a1" } as any);
    expect(read()).toMatchObject({ phase: "working", lastTurn: { agentId: "a1" }, agents: [{ status: "completed" }] });
    expect(read().engagement).toBeUndefined();

    await $.turn.complete({ reason: "answer", answer: "done", durationMs: 42, isAborted: false, turnId: "t1" } as any);
    expect(read()).toMatchObject({ phase: "idle", lastTurn: { reason: "answer", agentId: null },
      engagement: { turnId: "t1", durationMs: 42, answerChars: 4 } });

    await $.session.measure({ context: { tokens: 50_000, window: 200_000, percent: 25 },
      rateLimits: [{ kind: "five_hour", percentUsed: 61, resetsAt: "2026-10-03T23:00:00Z" }], changed: ["context"] } as any);
    expect(read()).toMatchObject({ context: { percent: 25 }, rateLimits: [{ kind: "five_hour", percentUsed: 61 }] });

    await $.turn.start({ text: "again", turnId: "t2" } as any);
    await $.turn.complete({ reason: "aborted", answer: "", durationMs: 3, isAborted: true, turnId: "t2" } as any);
    expect(read()).toMatchObject({ phase: "aborted", engagement: { turnId: "t1" } });

    await $.session.end({ reason: "other", sessionId: "sess-1", resume: {} } as any);
    expect(read()).toMatchObject({ phase: "ended", endReason: "other" });

    // Every write went tmp -> final via mv; no tmp file is left behind.
    expect(argvs.every((a) => a[0] === "/bin/mv" && a[3] === "/truth/sess-1.json")).toBe(true);
    expect([...files.keys()]).toEqual(["/truth/sess-1.json"]);
    // seq is monotonic in the final file.
    expect(read().seq).toBe(argvs.length);
  });
});
