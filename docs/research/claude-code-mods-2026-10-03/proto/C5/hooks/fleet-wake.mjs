// fleet-wake (C5 prototype): host-held timers that wake an idle session.
//  1. Mail: every POLL_MS, peek this pane's mailbox (lines past the drain's .seen cursor). When mail
//     is waiting and no turn is running, submit one wake prompt. The existing UserPromptSubmit drain
//     (hooks/mailbox-drain.sh) stays the only cursor owner and attaches the bodies to that turn.
//  2. Rate limit: when the main loop's turn dies with StopFailure error=rate_limit, arm one timer at
//     the window's resetsAt plus jitter and submit "continue" in place. No new process, no keystroke.
//  3. /inbox: status, or `/inbox now` to force a wake.

const POLL_MS = 15_000;
const FALLBACK_MS = 5 * 60_000; // no resetsAt reported: retry after 5 min
const JITTER_MS = 30_000; // + up to 30 s more, so 4 accounts' sessions do not all resume in the same second

const BOX = { plugin: "fleet-wake", key: "box" };
const WOKE = { plugin: "fleet-wake", key: "wokeAt" };
const BUSY = { plugin: "fleet-wake", key: "inflight" };
const LIMITS = { plugin: "fleet-wake", key: "limits" };
const RESUME = { plugin: "fleet-wake", key: "resumeAt" };

let poller = null; // module-level: a hot reload cancels the old env's timers, session.start re-arms
let resumer = null;

export function register(on) {
  on("session.start", async ($, e, next) => {
    const r = await next(e);
    const raw = (await $.env.get("CC_PANE_ID")) ?? (await $.env.get("ITERM_SESSION_ID")) ?? "";
    const box = raw.split(":").pop() || null; // same key mailbox-drain.sh derives
    await $.state.set(BOX, box);
    await $.command.register({ name: "inbox", description: "Mailbox wake status; `/inbox now` forces a wake", argumentHint: "[now]" });
    poller?.cancel();
    poller = $.clock.every(POLL_MS, () => void poll($, false));
    const at = ((await $.state.get(RESUME)).value ?? 0);
    if (at > 0) arm($, at - (await $.clock.now()));
    return r;
  });

  on("turn.start", async ($, e, next) => {
    await $.state.set(BUSY, true);
    return next(e);
  });

  on("turn.complete", async ($, e, next) => {
    const r = await next(e);
    if (!e.agentId) await $.state.set(BUSY, false);
    return r;
  });

  on("session.measure", async ($, e, next) => {
    if (e.rateLimits.length) await $.state.set(LIMITS, e.rateLimits.map(({ kind, percentUsed, resetsAt }) => ({ kind, percentUsed, resetsAt })));
    return next(e);
  });

  on("classic.StopFailure", async ($, e, next) => {
    const r = await next(e);
    if (e.error !== "rate_limit" || e.agent_id) return r;
    const now = await $.clock.now();
    const due = resetTime(((await $.state.get(LIMITS)).value ?? []), now) ?? now + FALLBACK_MS;
    const at = due + JITTER_MS + Math.floor(Math.random() * JITTER_MS);
    await $.state.set(RESUME, at);
    arm($, at - now);
    $.ui.toast(`fleet-wake: rate limited, resuming at ${new Date(at).toLocaleTimeString()}`);
    return r;
  });

  on("session.end", async ($, e, next) => {
    poller?.cancel(); resumer?.cancel();
    return next(e);
  });

  on("command.run", { command: "inbox" }, async ($, e) => {
    if (e.args.trim() === "now") return { text: (await poll($, true)) ? "wake submitted" : "no mail pending" };
    const box = ((await $.state.get(BOX)).value ?? null);
    const at = ((await $.state.get(RESUME)).value ?? 0);
    const p = box ? await pending($, box) : null;
    return { text: `box ${box ?? "(none: no CC_PANE_ID/ITERM_SESSION_ID)"} · pending ${p?.n ?? "?"} · ${at ? `resume at ${new Date(at).toISOString()}` : "no resume armed"}` };
  });
}

// Earliest future reset among exhausted windows; else the latest future reset reported.
function resetTime(limits, now) {
  const fut = limits.map((l) => ({ ...l, t: Date.parse(l.resetsAt ?? "") })).filter((l) => l.t > now);
  const full = fut.filter((l) => l.percentUsed >= 100);
  if (full.length) return Math.max(...full.map((l) => l.t));
  return fut.length ? Math.min(...fut.map((l) => l.t)) : undefined;
}

function arm($, ms) {
  resumer?.cancel();
  resumer = $.clock.after(Math.max(0, ms), () => void resume($));
}

async function resume($) {
  await $.state.set(RESUME, 0);
  await $.state.set(BUSY, true);
  void $.prompt.submit({ text: "[fleet-wake] The rate-limit window has reset. Continue the task you were working on when the limit hit; any mailbox lines are attached." });
}

async function pending($, box) {
  const dir = (await $.env.get("CC_MAILBOX_DIR")) ?? `${await $.env.get("HOME")}/.claude/mailbox`;
  const text = await $.fs.read(`${dir}/${box}.md`).catch(() => "");
  const lines = typeof text === "string" ? text.split("\n").filter(Boolean).length : 0;
  const seen = parseInt(String(await $.fs.read(`${dir}/${box}.seen`).catch(() => "0")).trim(), 10) || 0;
  return { lines, n: Math.max(0, lines - Math.min(seen, lines)) };
}

async function poll($, force) {
  const box = ((await $.state.get(BOX)).value ?? null);
  if (!box) return false;
  if (!force && ((((await $.state.get(BUSY)).value ?? false)) || (((await $.state.get(RESUME)).value ?? 0)) > 0)) return false;
  const { lines, n } = await pending($, box);
  if (n === 0 || (!force && lines <= (((await $.state.get(WOKE)).value ?? 0)))) return false;
  await $.state.set(WOKE, lines);
  await $.state.set(BUSY, true);
  void $.prompt.submit({ text: `[fleet-wake] ${n} new mailbox line(s) arrived while this session was idle. They are attached by the mailbox drain; read and act on them.` });
  return true;
}
