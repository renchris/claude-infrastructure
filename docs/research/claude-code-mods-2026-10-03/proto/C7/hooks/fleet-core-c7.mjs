// fleet-core C7: teammate lifecycle, lead side (scratch prototype).
// Tracks teammates/background agents, blocks the lead's Stop once while idle
// teammates are still resident and the lead's tree is clean, and exports the
// roster as JSON for wrap-ledger's RESIDENT_MINE to read.

const ROSTER = { plugin: "fleet-core-c7", key: "roster" };
const BLOCKED = { plugin: "fleet-core-c7", key: "blockedFor" };
const LIVE = new Set(["pending", "running", "waiting", "idle"]);

export function register(on) {
  on("agent.spawn", async ($, e, next) => {
    const r = await next(e);
    if (r?.agentId) {
      await upsert($, [{ id: r.agentId, teammateId: r.teammateId, name: e.name,
        description: e.description, status: "running", parentId: e.parentAgentId }]);
    }
    return r;
  });

  on("classic.TeammateIdle", async ($, e, next) => {
    const r = await next(e);
    const address = `${e.teammate_name}@${e.team_name}`;
    await upsert($, [{ id: address, teammateId: address, name: e.teammate_name, status: "idle" }]);
    return r;
  });

  on("classic.Stop", async ($, e, next) => {
    const r = await next(e);
    if (e.agent_id || e.stop_hook_active || r?.block) return r; // lead's main loop, first stop only
    const roster = await refresh($);
    const resident = Object.values(roster).filter((m) => m.teammateId && LIVE.has(m.status));
    const idle = resident.filter((m) => m.status === "idle");
    if (idle.length === 0) return r;
    const git = await $.process.run(["git", "status", "--porcelain"], { timeoutMs: 5000 })
      .catch(() => ({ exitCode: 1, stdout: "" }));
    if (git.exitCode === 0 && git.stdout.trim() !== "") return r; // own work not committed yet
    const signature = idle.map((m) => m.teammateId).sort().join(",");
    const { value: already } = await $.state.get(BLOCKED);
    if (already === signature) return r; // block once per idle set
    await $.state.set(BLOCKED, signature);
    return { ...r, block: message(idle, resident.filter((m) => m.status !== "idle")) };
  });

  on("session.end", async ($, e, next) => {
    const r = await next(e);
    await refresh($).catch((err) => $.ui.log(`fleet-core-c7 export failed: ${err?.message ?? err}`, { to: "debug" }));
    return r;
  });
}

async function refresh($) {
  const list = await $.agent.list();
  return upsert($, list.map((a) => ({ id: a.id, teammateId: a.teammateId, name: a.name,
    description: a.description, status: a.status, parentId: a.parentId })));
}

async function upsert($, members) {
  const { value: roster = {} } = await $.state.get(ROSTER);
  const now = await $.clock.now();
  const next = { ...roster };
  for (const m of members) {
    const key = m.teammateId ?? m.id;
    next[key] = { ...next[key], ...strip(m), seenAt: now };
  }
  await $.state.set(ROSTER, next);
  await exportRoster($, next);
  return next;
}

async function exportRoster($, roster) {
  const dir = (await $.env.get("CLAUDE_CONFIG_DIR")) ?? `${await $.env.get("HOME")}/.claude`;
  const sid = await $.session.id();
  const members = Object.values(roster).filter((m) => m.teammateId);
  const doc = { sessionId: sid, writtenAt: await $.clock.now(),
    residentMine: members.filter((m) => LIVE.has(m.status)).map((m) => m.name ?? m.teammateId),
    members };
  await $.fs.write(`${dir}/fleet-core/roster-${sid}.json`, JSON.stringify(doc, null, 2) + "\n");
}

function message(idle, busy) {
  const targets = idle.map((m) => `${m.name ?? m.teammateId} (${m.teammateId})`).join(", ");
  const lines = [
    `fleet-core: ${idle.length} teammate(s) you started are idle and still resident: ${targets}.`,
    `Send each a shutdown_request: ${idle.map((m) => `SendMessage({to: "${m.name ?? m.teammateId}", message: {type: "shutdown_request"}})`).join("; ")}.`,
    "Escalate to TaskStop(<teammateId>) after ~60 s. To keep a member, say so in the close as a stated park.",
  ];
  if (busy.length) lines.push(`Still running (not blocking on these): ${busy.map((m) => m.name ?? m.teammateId).join(", ")}.`);
  return lines.join("\n");
}

function strip(o) {
  return Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined));
}
