import { describe, expect, mock, test } from "claude-code/testing";

const MB = "/mb";

function world($: any, on: any) {
  const files: Record<string, string> = {};
  const submitted: string[] = [];
  const clock = mock.clock(on, { now: Date.parse("2026-10-03T12:00:00Z") });
  mock.env(on, { CC_PANE_ID: "w0t0p0:ABCD-1234", CC_MAILBOX_DIR: MB, HOME: "/home" });
  on("fs.read", ($: any, e: any) => (e.path in files ? { value: files[e.path] } : { deny: `ENOENT ${e.path}` }));
  on("prompt.submit", ($: any, e: any) => { submitted.push(e.text); return { text: e.text }; });
  on("session.start", ($: any, e: any) => ({ cwd: e.cwd }));
  on("command.register", () => ({ value: { command: "inbox" } }));
  on("turn.start", ($: any, e: any) => ({ turnId: e.turnId }));
  on("turn.complete", () => ({ text: "" }));
  on("session.measure", ($: any, e: any) => ({ changed: e.changed }));
  on("classic.StopFailure", () => ({}));
  on("ui.toast", () => ({ value: undefined }));
  return { files, submitted, clock };
}

describe("fleet-wake", () => {
  test("idle mail wakes the session once per new line, never mid-turn", async ($, on) => {
    const w = world($, on);
    await $.session.start({ surface: "terminal", isInteractive: true, cwd: "/work" } as any);

    await w.clock.advance(15_000);
    expect(w.submitted.length).toBe(0); // no mailbox yet

    w.files[`${MB}/ABCD-1234.md`] = "2026-10-03T12:00:10+0000 [peer] hello\n";
    await w.clock.advance(15_000);
    expect(w.submitted.length).toBe(1);
    expect(w.submitted[0]).toMatch(/1 new mailbox line/);

    await w.clock.advance(15_000); // wake still in flight: no second submit
    expect(w.submitted.length).toBe(1);

    await $.turn.complete({ reason: "answer", answer: "ok", durationMs: 1 } as any);
    w.files[`${MB}/ABCD-1234.seen`] = "1"; // the drain hook consumed it
    await w.clock.advance(15_000);
    expect(w.submitted.length).toBe(1);

    w.files[`${MB}/ABCD-1234.md`] += "2026-10-03T12:01:10+0000 [peer] again\n";
    await w.clock.advance(15_000);
    expect(w.submitted.length).toBe(2);
  });

  test("a rate-limited turn resumes in place after resetsAt plus jitter", async ($, on) => {
    const w = world($, on);
    await $.session.start({ surface: "terminal", isInteractive: true, cwd: "/work" } as any);
    const reset = w.clock.now() + 10 * 60_000;
    await $.session.measure({
      context: { window: 200_000 } as any,
      rateLimits: [{ kind: "five_hour", percentUsed: 100, resetsAt: new Date(reset).toISOString() }],
      changed: ["rateLimits"],
    } as any);
    await $.classic.StopFailure({ error: "rate_limit" } as any);
    await $.turn.complete({ reason: "error", answer: "", durationMs: 1 } as any);

    await w.clock.advance(10 * 60_000 + 29_000); // before reset + minimum jitter
    expect(w.submitted.length).toBe(0);
    await w.clock.advance(31_000); // past reset + maximum jitter
    expect(w.submitted.length).toBe(1);
    expect(w.submitted[0]).toMatch(/rate-limit window has reset/);
  });

  test("/inbox reports the box and pending count", async ($, on) => {
    const w = world($, on);
    await $.session.start({ surface: "terminal", isInteractive: true, cwd: "/work" } as any);
    w.files[`${MB}/ABCD-1234.md`] = "a\nb\nc\n";
    w.files[`${MB}/ABCD-1234.seen`] = "1";
    const r: any = await $.command.run({ command: "inbox", args: "" } as any);
    expect(r.text).toMatch(/box ABCD-1234 · pending 2/);
  });
});
