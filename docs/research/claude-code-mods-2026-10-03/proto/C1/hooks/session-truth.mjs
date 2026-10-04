// session-truth: observe-only. One record per session in $.state, mirrored to
// $CC_SESSION_TRUTH_DIR/<session_id>.json (tmp file + mv) on every change.
// Every hook passes the event on unchanged; a failure here leaves today's behavior.

const RECORD = { plugin: "session-truth", key: "record" };
const PHASE_OF = { answer: "idle", refusal: "idle", aborted: "aborted", error: "errored" };

let lastSeq = 0; // per load; a reload only lets the next (higher) seq through
let queue = Promise.resolve(); // serialises file writes within this load

export function register(on) {
  on("session.start", async ($, e, next) => {
    const r = await next(e);
    await safe(() => update($, async () => ({
      ...blank(), sessionId: await $.session.id(), cwd: r?.cwd ?? e.cwd, isInteractive: e.isInteractive,
    }), true));
    return r;
  });

  // Main loop only: a subagent's run raises no turn.start (index.d.ts TurnCompleteFields.turnId).
  on("turn.start", async ($, e, next) => {
    const r = await next(e);
    await safe(() => update($, () => ({ phase: "working", turnId: e.turnId })));
    return r;
  });

  on("turn.complete", async ($, e, next) => {
    const r = await next(e);
    await safe(() => update($, async (rec) => {
      const at = await $.clock.now();
      const patch = {
        lastTurn: {
          turnId: e.turnId, reason: e.reason, agentId: e.agentId ?? null,
          durationMs: e.durationMs, isAborted: e.isAborted, usage: e.usage ?? null, at,
        },
      };
      if (e.agentId) return { ...patch, agents: await roster($) };
      patch.phase = PHASE_OF[e.reason] ?? "idle";
      if (!rec.engagement && e.reason === "answer" && (e.answer ?? "").trim()) {
        patch.engagement = { turnId: e.turnId, at, durationMs: e.durationMs, answerChars: e.answer.length };
      }
      return patch;
    }));
    return r;
  });

  on("session.measure", async ($, e, next) => {
    const r = await next(e);
    await safe(() => update($, () => ({
      context: { tokens: e.context?.tokens, window: e.context?.window, percent: e.context?.percent },
      rateLimits: (e.rateLimits ?? []).map(({ kind, percentUsed, resetsAt }) => ({ kind, percentUsed, resetsAt })),
    })));
    return r;
  });

  on("agent.spawn", async ($, e, next) => {
    const r = await next(e);
    if (!r?.deny) await safe(() => update($, async () => ({ agents: await roster($) })));
    return r;
  });

  on("classic.TeammateIdle", async ($, e, next) => {
    const r = await next(e);
    await safe(() => update($, async () => ({ agents: await roster($) })));
    return r;
  });

  // session.end: the whole chain shares one short bound; write first, then pass on.
  on("session.end", async ($, e, next) => {
    await safe(() => update($, () => ({ phase: "ended", endReason: e.reason })));
    return next(e);
  });
}

function blank() {
  return { schema: 1, phase: "starting", agents: [], seq: 0, updatedAt: 0 };
}

async function roster($) {
  const list = await $.agent.list();
  return list.map(({ id, teammateId, type, status, parentId, name }) => ({ id, teammateId, type, status, parentId, name }));
}

// Compare-and-set on the host-held record, so concurrent hooks (main + subagents) never lose a field.
async function update($, patchOf, reset = false) {
  for (let i = 0; i < 5; i++) {
    const { value, version } = await $.state.get(RECORD);
    const base = reset || !value ? blank() : value;
    const seq = (value?.seq ?? 0) + 1;
    const rec = { ...base, ...(await patchOf(base)), seq, updatedAt: await $.clock.now() };
    const res = await $.state.set(RECORD, rec, { ifVersion: version });
    if (res.isSet) return flush($, rec);
  }
}

function flush($, rec) {
  queue = queue.then(() => writeFile($, rec)).catch(() => {});
  return queue;
}

async function writeFile($, rec) {
  if (rec.seq <= lastSeq || !rec.sessionId) return;
  const dir = await $.env.get("CC_SESSION_TRUTH_DIR");
  if (!dir) return;
  lastSeq = rec.seq;
  const final = `${dir}/${rec.sessionId}.json`;
  const tmp = `${final}.${rec.seq}.tmp`;
  await $.fs.write(tmp, JSON.stringify(rec) + "\n");
  await $.process.run(["/bin/mv", "-f", tmp, final], { timeoutMs: 5000 }); // no $.fs.rename
}

async function safe(fn) {
  try { await fn(); } catch { /* observe-only: never disturb the chain */ }
}
