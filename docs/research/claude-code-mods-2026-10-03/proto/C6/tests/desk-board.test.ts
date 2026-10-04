import { describe, expect, mock, test } from "claude-code/testing";

const NOW = Date.parse("2026-10-03T12:00:00Z");
const DIR = "/h/.claude/state/desk/sessions";

function world(on: any, files: Record<string, string>) {
  const opened: string[] = [];
  const statuses: (string | undefined)[] = [];
  const clock = mock.clock(on, { now: NOW });
  mock.env(on, { HOME: "/h" });
  on("session.start", ($: any, e: any) => ({ cwd: e.cwd }));
  on("command.register", ($: any, e: any) => ({ value: { command: e.name } }));
  on("fs.list", ($: any, e: any) => ({
    value: e.path === DIR
      ? Object.keys(files).filter((p) => p.startsWith(DIR)).map((p) => ({
          name: p.slice(DIR.length + 1), kind: "file", size: 1, mtimeMs: NOW - 1_000, isLink: false }))
      : [],
  }));
  on("fs.read", ($: any, e: any) => (files[e.path] === undefined ? { deny: `ENOENT: ${e.path}` } : { value: files[e.path] }));
  on("ui.open", ($: any, e: any) => { opened.push(e.id); return { value: { isPlaced: true } }; });
  on("ui.status", ($: any, e: any) => { statuses.push(e.text); return { value: undefined }; });
  return { opened, statuses, clock };
}

const ACCOUNTS = JSON.stringify({ rows: [
  { acct: "next", session_pct: 42, session_reset_at: "2026-10-03T14:13:00Z", weekly_pct: 18, weekly_reset_at: "2026-10-08T04:00:00Z" },
  { acct: "secondary", session_pct: 100, session_reset_at: "2026-10-03T13:00:00Z", weekly_pct: 100, weekly_reset_at: null },
] });

const PANE = {
  plugin: "desk-board", surface: "terminal", component: "Pane", requestId: "desk-board",
  viewport: { columns: 200, rows: 50, isFullscreen: true },
  props: { title: "Desk", isFocused: false, bodyColumns: 80, placement: "dock", scroll: { offset: 0, bodyRows: 40 }, view: {} },
};

describe("desk-board", () => {
  test("the pane lists sessions, a pending permission, idle teammates and both windows", async ($, on) => {
    const files: Record<string, string> = {
      "/tmp/claude-accounts-cache.json": ACCOUNTS,
      [`${DIR}/a.json`]: JSON.stringify({ sid: "a", label: "desk", account: "next", phase: "working", fill: 31, pending: null, idleTeammates: [] }),
    };
    const w = world(on, files);
    await $.session.start({ surface: "terminal", isInteractive: true, cwd: "/work" });
    expect(w.opened).toEqual(["desk-board"]);
    expect(w.statuses.at(-1)).toBe("desk: 1 live, 1/2 accounts open");

    const ui = await $.ui.mount(PANE as any);
    expect(await ui.find({ type: "Text", text: /next\s+5h\s+42% 2h13m\s+wk\s+18% 4d16h/ })).toBeDefined();
    expect(await ui.find({ type: "Text", text: /desk\s+working\s+31%\s+next/ })).toBeDefined();

    files[`${DIR}/b.json`] = JSON.stringify({ sid: "b", label: "handoff-7", account: "secondary", phase: "blocked", fill: 77,
      pending: { tool: "Bash", command: "git push --force origin main" }, idleTeammates: ["reviewer", "tester"] });
    await w.clock.advance(5_000);
    expect(await ui.find({ type: "Text", text: /waiting: Bash git push --force origin main/ })).toBeDefined();
    expect(await ui.find({ type: "Text", text: /idle: reviewer, tester/ })).toBeDefined();
    expect(w.statuses.at(-1)).toBe("desk: 2 live, 1 waiting on you, 1/2 accounts open");
    await ui.unmount();
  });

  test("a headless session opens nothing and polls nothing", async ($, on) => {
    const w = world(on, {});
    await $.session.start({ surface: null, isInteractive: false, cwd: "/work" });
    await w.clock.advance(20_000);
    expect(w.opened).toEqual([]);
    expect(w.statuses).toEqual([]);
  });
});
