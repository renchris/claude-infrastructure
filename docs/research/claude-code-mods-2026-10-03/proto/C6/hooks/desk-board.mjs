// desk-board (C6 prototype): one docked Pane over every live session and every account's
// 5-hour and weekly windows, plus a one-line $.ui.status summary. Interactive sessions only.
//
// Inputs (read-only, through $.fs):
//   C1 session files: <HOME>/.claude/state/desk/sessions/*.json, one per live session, shape
//     { sid, label, account, phase, fill, pending: {tool, command} | null, idleTeammates: [] }
//     ASSUMED contract: C1 and C2 do not exist yet; this is the shape C6 needs from them.
//   Account windows: /tmp/claude-accounts-cache.json, written by `claude-accounts --keepwarm`
//     (rows[].acct, session_pct, session_reset_at, weekly_pct, weekly_reset_at).

const BOARD = { plugin: "desk-board", key: "board" };
const PANE_ID = "desk-board";
const POLL_MS = 5_000;
const STALE_MS = 10 * 60_000;
const ACCOUNTS_CACHE = "/tmp/claude-accounts-cache.json";

export function register(on) {
  on("session.start", async ($, e, next) => {
    const result = await next(e);
    if (!e.isInteractive) return result; // headless fires, -p and SDK runs draw nothing
    await $.command.register({ name: "desk", description: "Show the desk board pane" });
    await refresh($);
    await $.ui.open({ id: PANE_ID, title: "Desk" });
    $.clock.every(POLL_MS, () => void refresh($).catch(() => undefined));
    return result;
  });

  on("command.run", { command: "desk" }, async ($) => {
    await refresh($);
    const opened = await $.ui.open({ id: PANE_ID, title: "Desk", focus: true });
    return { text: opened.isPlaced ? "Desk board shown" : "Desk board waiting for a wider terminal" };
  });

  on("ui.render", { component: "Pane" }, async ($, e, next) => {
    if (e.requestId !== PANE_ID) return next(e);
    const { value: board } = await $.state.get(BOARD); // subscribes this drawing to every set
    const { Box, Text, Button } = $.ui.resolve(e);
    const now = await $.clock.now();
    const rows = [];
    if (!board) {
      rows.push(Text({ dimColor: true, children: "reading..." }));
    } else {
      rows.push(Text({ bold: true, children: "Accounts" }));
      for (const a of board.accounts) {
        rows.push(Text({ dimColor: a.sessionPct >= 100 || a.weeklyPct >= 100,
          children: `${a.acct.padEnd(11)} 5h ${pct(a.sessionPct)} ${until(a.sessionResetAt, now)}  wk ${pct(a.weeklyPct)} ${until(a.weeklyResetAt, now)}` }));
      }
      rows.push(Text({ bold: true, children: `Sessions (${board.sessions.length})` }));
      for (const s of board.sessions) {
        rows.push(Text({ children: `${s.label.padEnd(18)} ${s.phase.padEnd(9)} ${pct(s.fill)}  ${s.account}` }));
        if (s.pending) rows.push(Text({ color: "yellow", children: `  waiting: ${s.pending.tool} ${s.pending.command}` }));
        if (s.idleTeammates.length) rows.push(Text({ dimColor: true, children: `  idle: ${s.idleTeammates.join(", ")}` }));
      }
      for (const err of board.errors) rows.push(Text({ color: "red", children: err }));
    }
    rows.push(Button({ key: "refresh", label: "Refresh", hotkey: "r", onPress: () => refresh($) }));
    return Box({ flexDirection: "column", paddingX: 1, children: rows });
  });
}

async function refresh($) {
  const now = await $.clock.now();
  const home = (await $.env.get("HOME")) ?? "";
  const dir = `${home}/.claude/state/desk/sessions`;
  const errors = [];
  const sessions = [];
  let entries = [];
  try { entries = await $.fs.list(dir); } catch { errors.push(`no session files at ${dir}`); }
  for (const ent of entries) {
    if (ent.kind !== "file" || !ent.name.endsWith(".json") || now - ent.mtimeMs > STALE_MS) continue;
    try { sessions.push(asSession(JSON.parse(await $.fs.read(`${dir}/${ent.name}`)))); } catch { /* torn write: next poll */ }
  }
  let accounts = [];
  try {
    const cache = JSON.parse(await $.fs.read(ACCOUNTS_CACHE));
    accounts = (cache.rows ?? []).map((r) => ({ acct: String(r.acct), sessionPct: r.session_pct ?? null,
      sessionResetAt: r.session_reset_at ?? null, weeklyPct: r.weekly_pct ?? null, weeklyResetAt: r.weekly_reset_at ?? null }));
  } catch { errors.push("accounts cache unreadable"); }
  const board = { at: now, sessions, accounts, errors };
  await $.state.set(BOARD, board);
  $.ui.status(summary(board));
}

function asSession(j) {
  return { sid: String(j.sid), label: String(j.label ?? j.sid), account: String(j.account ?? "?"), phase: String(j.phase ?? "?"),
    fill: Number(j.fill ?? 0), pending: j.pending ? { tool: String(j.pending.tool), command: String(j.pending.command) } : null,
    idleTeammates: Array.isArray(j.idleTeammates) ? j.idleTeammates.map(String) : [] };
}

function summary(b) {
  const waiting = b.sessions.filter((s) => s.pending).length;
  const open = b.accounts.filter((a) => (a.sessionPct ?? 0) < 100 && (a.weeklyPct ?? 0) < 100).length;
  return `desk: ${b.sessions.length} live` + (waiting ? `, ${waiting} waiting on you` : "") + `, ${open}/${b.accounts.length} accounts open`;
}

function pct(n) { return n == null ? "  -" : `${String(Math.round(n)).padStart(3)}%`; }

function until(iso, now) {
  const ms = iso ? Date.parse(iso) - now : NaN;
  if (!(ms > 0)) return "";
  const m = Math.round(ms / 60_000);
  return m >= 1440 ? `${Math.floor(m / 1440)}d${Math.floor((m % 1440) / 60)}h` : `${Math.floor(m / 60)}h${m % 60}m`;
}
