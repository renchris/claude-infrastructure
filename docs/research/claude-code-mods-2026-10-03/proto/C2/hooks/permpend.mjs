// fleet-permpend (C2): permission-pending beacon v2.
//
// Writes the SAME beacon the shell hook does (CC_PERMPEND_DIR/<sid>.json, {ts, tool_name, tool_input,
// cwd, tool_use_id}, heartbeat .beacon-alive) so lead-supervisor/cc-blockers read it unchanged, but:
//   - the ask is keyed by the engine's own tool_use_id (tool.check carries it; PermissionRequest does not),
//   - the beacon is cleared only when THAT call's next() resolves (no collateral PostToolUse clears),
//   - the archive row carries what caused the ask (tool.check reason / rule / hook) and the exact outcome.
// Optional: CC_UNATTENDED=1 answers the prompt with deny + a cc-backlog route instead of hanging.

const ASKS = { plugin: "fleet-permpend", key: "asks" };
const UNMATCHED = "unmatched:";            // a PermissionRequest no ask could be paired with

let chain = Promise.resolve();              // serialises this session's beacon file ops
const serial = (fn) => { const p = chain.then(fn, fn); chain = p.catch(() => {}); return p; };
const loopOf = new Map();                   // tool_use_id -> agentId, while the call is in flight

const now = () => Math.floor(Date.now() / 1000);
const sortKeys = (v) => Array.isArray(v) ? v.map(sortKeys)
  : v && typeof v === "object" ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, sortKeys(v[k])])) : v;
const canon = (v) => JSON.stringify(sortKeys(v ?? {}));
const SAFE = /^[A-Za-z0-9._-]+$/;

async function dirs($) {
  const home = (await $.env.get("HOME")) ?? "/tmp";
  return {
    pend: (await $.env.get("CC_PERMPEND_DIR")) || "/tmp/cc-permission-pending",
    arch: (await $.env.get("CC_PERMARCHIVE_DIR")) || `${home}/.claude/autonomy/permission-archive`,
  };
}

async function writeBeacon($, ask, toolInput) {
  const { pend } = await dirs($);
  if (!SAFE.test(ask.sessionId)) return;
  const tmp = `${pend}/.${ask.sessionId}.${ask.id.replace(/[^A-Za-z0-9_-]/g, "_")}.tmp`;
  const body = { ts: ask.promptedAt, tool_name: ask.tool, tool_input: toolInput ?? ask.input ?? {},
    cwd: ask.cwd, tool_use_id: ask.id.startsWith(UNMATCHED) ? "" : ask.id, source: "mod:fleet-permpend" };
  await $.fs.write(`${pend}/.beacon-alive`, "");
  await $.fs.write(tmp, JSON.stringify(body));                       // no atomic write/rename in $.fs:
  await $.process.run(["/bin/mv", "-f", tmp, `${pend}/${ask.sessionId}.json`]); // rename via a process
}

async function archive($, ask, outcome, denyText) {
  const { arch } = await dirs($);
  const t = now(), d = new Date(t * 1000);
  const mon = `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
  const row = { session_id: ask.sessionId, ts: ask.promptedAt, resolved_ts: t, waited_s: t - ask.promptedAt,
    resolved_by: "mod:tool.call", cleared_tool: ask.tool, cleared_tool_use_id: ask.id,
    tool_use_id: ask.id, tool_name: ask.tool, tool_input: ask.input, cwd: ask.cwd, agent_id: ask.agentId,
    outcome, deny_text: denyText ?? "", auto_denied: ask.autoDenied,
    check_reason: ask.reason, check_rule: ask.rule, check_hook: ask.hook, asked_ts: ask.askedAt };
  // $.fs has no append: one sidecar file per row, matched by the harvester's *.jsonl glob.
  await $.fs.write(`${arch}/${mon}.${ask.sessionId}.mod-${ask.id.replace(/[^A-Za-z0-9_-]/g, "_")}.jsonl`,
    JSON.stringify(row) + "\n");
}

// After an ask leaves, point the beacon at the oldest still-prompted ask of the session, or remove it.
async function repoint($, asks, sessionId) {
  const left = Object.values(asks).filter((a) => a.sessionId === sessionId && a.promptedAt && !a.autoDenied)
    .sort((a, b) => a.promptedAt - b.promptedAt);
  if (left.length) return writeBeacon($, left[0]);
  const { pend } = await dirs($);
  await $.fs.write(`${pend}/.beacon-alive`, "");
  if (SAFE.test(sessionId)) await $.process.run(["/bin/rm", "-f", `${pend}/${sessionId}.json`]); // no $.fs delete
}

export function register(on) {
  on("tool.call", async ($, e, next) => {
    const id = e.tool_use_id;
    if (id) loopOf.set(id, e.agentId ?? "");
    let r, outcome = "threw";
    try {
      r = await next(e);
      outcome = r && r.deny !== undefined ? "denied" : r && r.isError ? "errored" : "ran";
      return r;
    } finally {
      if (id) {
        loopOf.delete(id);
        await serial(async () => {
          const { value: asks = {} } = await $.state.get(ASKS);
          const ask = asks[id];
          if (!ask) return;
          const rest = { ...asks }; delete rest[id];
          await $.state.set(ASKS, rest);
          if (ask.promptedAt) { await archive($, ask, outcome, r && r.deny); await repoint($, rest, ask.sessionId); }
        });
      }
    }
  });

  on("tool.check", async ($, e, next) => {
    const v = await next(e);
    if (v && v.decision === "ask" && e.tool_use_id) {
      const id = e.tool_use_id;
      await serial(async () => {
        const { value: asks = {} } = await $.state.get(ASKS);
        await $.state.set(ASKS, { ...asks, [id]: { id, tool: e.tool, input: e.input ?? {},
          agentId: loopOf.get(id) ?? "", askedAt: now(), reason: v.reason ?? "", rule: v.rule ?? "",
          hook: v.hook ?? "", promptedAt: 0, sessionId: "", cwd: "", autoDenied: false } });
      });
    }
    return v;
  });

  on("classic.PermissionRequest", async ($, e, next) => {
    const unattended = (await $.env.get("CC_UNATTENDED")) === "1";
    const ask = await serial(async () => {
      const { value: asks = {} } = await $.state.get(ASKS);
      // PermissionRequest carries no tool_use_id: pair it with an open, un-prompted ask of the same
      // loop and tool, preferring an identical input, else the newest.
      const pool = Object.values(asks).filter((a) => !a.promptedAt && a.tool === e.tool_name
        && a.agentId === (e.agent_id ?? "")).sort((a, b) => b.askedAt - a.askedAt);
      const hit = pool.find((a) => canon(a.input) === canon(e.tool_input)) ?? pool[0];
      const base = hit ?? { id: `${UNMATCHED}${now()}`, tool: e.tool_name, input: e.tool_input ?? {},
        agentId: e.agent_id ?? "", askedAt: now(), reason: "", rule: "", hook: "" };
      const a = { ...base, promptedAt: now(), sessionId: e.session_id, cwd: e.cwd ?? "", autoDenied: unattended };
      await $.state.set(ASKS, { ...asks, [a.id]: a });
      if (!unattended) await writeBeacon($, a, e.tool_input);
      return a;
    });
    if (!unattended) return next(e);
    const why = [ask.rule && `rule ${ask.rule}`, ask.hook && `hook ${ask.hook}`, ask.reason].filter(Boolean).join("; ");
    return { decision: { behavior: "deny", message:
      `Unattended session: no one can answer this permission prompt for ${ask.tool}${why ? ` (${why})` : ""}. ` +
      `Do not retry it or work around it. File the step with: cc-backlog needs "<the exact step>" --class needs-human, then continue with other work.` } };
  });

  // An unpaired prompt has no call to clear it: the main loop's Stop does, as the shell hook's Stop does.
  on("classic.Stop", async ($, e, next) => {
    const r = await next(e);
    await serial(async () => {
      const { value: asks = {} } = await $.state.get(ASKS);
      const orphans = Object.keys(asks).filter((k) => k.startsWith(UNMATCHED));
      if (!orphans.length) return;
      const rest = { ...asks }; for (const k of orphans) delete rest[k];
      await $.state.set(ASKS, rest);
      await repoint($, rest, e.session_id);
    });
    return r;
  });
}
