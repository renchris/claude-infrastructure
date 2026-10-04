// spawn-governor: keeps fan-out inside what the lead's context can absorb.
//  1. agent.spawn: refuses a subagent/teammate spawn (before next) when the lead's context fill
//     plus the projected size of returns still outstanding would cross LIMIT_PERCENT, or when
//     the exact spawn depth (from parentAgentId, not a transcript_path guess) exceeds the cap.
//  2. tool.call Agent + prompt.submit task-notification: a return longer than CAP_CHARS goes to a
//     file; the lead reads the opening plus the path.

const AGENTS = { plugin: "spawn-governor", key: "agents" };
const LIMIT_PERCENT = 75;      // refuse when projected fill reaches this
const DEFAULT_RETURN = 6_000;  // tokens assumed for a return not yet seen
const CAP_CHARS = 16_000;      // ~4k tokens; longer returns spill to a file
const HEAD_CHARS = 2_000;      // what the lead still reads inline
const DEFAULT_MAX_DEPTH = 2;   // same default as agent-teams-enforce.sh CC_SPAWN_MAX_DEPTH

export function register(on) {
  on("agent.spawn", async ($, e, next) => {
    const agents = (await $.state.get(AGENTS)).value ?? {};
    const depth = e.parentAgentId ? (agents[e.parentAgentId]?.depth ?? 1) + 1 : 1;
    const reason = (await depthRefusal($, e, depth)) ?? (await fillRefusal($, e, agents));
    if (reason) return { deny: reason };               // before next(e): a deny after it does not block
    const r = await next(e);
    if (r.agentId) {
      const toLead = !e.parentAgentId;                 // a nested return lands in its parent, not the lead
      await $.state.set(AGENTS, {
        ...agents,
        [r.agentId]: {
          depth, parentAgentId: e.parentAgentId, isTeammate: e.isTeammate === true,
          background: e.background, projected: toLead ? DEFAULT_RETURN : 0, returned: !toLead,
        },
      });
    }
    return r;
  }).catch(async ($, e, next) =>
    next.called ? next(e) // the spawn happened; only the bookkeeping failed
      : { deny: `spawn-governor could not check this spawn (${next.error.kind}: ${next.error.message}); refused to stay safe. Retry once; if it repeats, do the task inline.` });

  on("tool.call", { tool: "Agent" }, async ($, e, next) => {
    const r = await next(e);
    if (!r.result || r.isError || r.result.status !== "completed") return r;
    await markReturned($, [r.result.agentId]);
    const text = r.result.content.map((c) => c.text).join("\n");
    if (text.length <= CAP_CHARS) return r;
    const capped = await spill($, r.result.agentId, text);
    return { result: { ...r.result, content: [{ type: "text", text: capped }] } };
  }).catch(($, e, next) => next(e)); // fail open: an uncapped return beats a lost one

  on("turn.complete", async ($, e, next) => {
    const r = await next(e);
    if (e.agentId) {
      const agents = (await $.state.get(AGENTS)).value ?? {};
      const a = agents[e.agentId];
      if (a && !a.returned) {
        // The answer is known now; until delivered it weighs what the lead will actually read.
        const projected = Math.ceil(Math.min(e.answer.length, CAP_CHARS) / 4);
        await $.state.set(AGENTS, { ...agents, [e.agentId]: { ...a, projected, returned: a.isTeammate } });
      }
    }
    return r;
  });

  on("prompt.submit", async ($, e, next) => {
    if (e.origin.kind !== "task-notification") return next(e);
    const agents = (await $.state.get(AGENTS)).value ?? {};
    const ids = Object.keys(agents).filter((id) => e.text.includes(id));
    await markReturned($, ids);
    if (e.text.length <= CAP_CHARS) return next(e);
    return next({ ...e, text: await spill($, ids[0] ?? "notification", e.text) });
  }).catch(($, e, next) => next(e));
}

async function depthRefusal($, e, depth) {
  const max = Number((await $.env.get("CC_SPAWN_MAX_DEPTH")) ?? DEFAULT_MAX_DEPTH);
  if (!(depth > max)) return null;
  return `spawn-governor: refused "${e.description}": it would run at depth ${depth}, cap ${max} (exact, from parentAgentId ${e.parentAgentId}). Return your findings to the agent that spawned you and let it decide whether to fan out.`;
}

async function fillRefusal($, e, agents) {
  if (e.parentAgentId) return null; // usage() reports the lead's window only; a nested spawn's parent is not measurable
  const { context } = await $.session.usage();
  if (!context?.window) return null;
  const used = context.tokens ?? Math.round(((context.percent ?? 0) * context.window) / 100);
  const open = Object.entries(agents).filter(([, a]) => !a.returned);
  const pending = open.reduce((s, [, a]) => s + a.projected, 0);
  const pct = Math.round(((used + pending + DEFAULT_RETURN) * 100) / context.window);
  if (pct < LIMIT_PERCENT) return null;
  const who = e.isTeammate ? "teammate" : "subagent";
  return `spawn-governor: refused ${who} "${e.description}". The lead's context is ${short(used)}/${short(context.window)} and ${open.length} agent return(s) are still outstanding (~${short(pending)} tokens); with this one it would reach ~${pct}% (limit ${LIMIT_PERCENT}%). Wait for outstanding agents to return, run /compact, or do this task inline.`;
}

async function markReturned($, ids) {
  const agents = (await $.state.get(AGENTS)).value ?? {};
  const hit = ids.filter((id) => agents[id] && !agents[id].returned);
  if (hit.length === 0) return;
  const next = { ...agents };
  for (const id of hit) next[id] = { ...agents[id], returned: true };
  await $.state.set(AGENTS, next);
}

async function spill($, agentId, text) {
  const path = `${await $.session.cwd()}/.claude/agent-returns/${await $.session.id()}/${agentId}.md`;
  await $.fs.write(path, text);
  return `${text.slice(0, HEAD_CHARS)}\n\n[spawn-governor: return truncated at ${HEAD_CHARS} of ${text.length} chars. Full text: ${path} (Read it only for the parts you need.)]`;
}

function short(n) {
  return n >= 1_000 ? `${+(n / 1_000).toFixed(1)}k` : String(n);
}
